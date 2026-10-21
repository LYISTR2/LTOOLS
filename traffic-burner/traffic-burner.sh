#!/bin/sh
# ============================================================================
# traffic-burner.sh v1.0 — 消耗本机流量的跨发行版脚本 (Debian / Ubuntu / Alpine)
#
# 纯 POSIX sh 编写(dash 与 BusyBox ash 通吃), 只依赖 curl (缺失时自动用 apt/apk 安装)。
# 已在 alpine:3.20 / debian:12 / ubuntu:24.04 容器实测。
#
# 流量统计: /proc/net/dev 前后差值 —— download 看 RX(下行), upload 看 TX(上行),
#           口径贴近厂商计费; 汇总同时给出双向流量与平均速率。
#
# 用法示例:
#   ./traffic-burner.sh -d 3600 -w 4                  # 跑 1 小时, 4 并发
#   ./traffic-burner.sh -t 500                        # 累计 500 MB 后自动停
#   ./traffic-burner.sh -w 8 -r 20M -t 2000           # 8 并发, 每并发限速 20MB/s
#   ./traffic-burner.sh -u "https://你的源/big.bin"    # 自定义下载源
#   ./traffic-burner.sh -m upload -u "http://你另一台机/up"   # 上行烧流量(需可接收POST的地址)
#   ./traffic-burner.sh -c                            # 只做平台自检, 不跑流量
#
# 常驻: nohup ./traffic-burner.sh -d 86400 >/dev/null 2>&1 &
# 停止: Ctrl-C 或 kill $(cat /tmp/traffic-burner.pid) —— 均会优雅收尾并打汇总
#
# 注意: 默认 URL 为公开测速节点(示例性质), 长期跑请换成自己可控的目标并遵守目标站条款;
#       同一台机同时只允许一个实例 (PID 文件 /tmp/traffic-burner.pid)。
# ============================================================================
set -u
set -f      # URL 含 ? & 等字符, 关闭通配展开更安全

DURATION=3600
TARGET_MB=0
WORKERS=2
RATE=""
URLS=""
URLS_FILE=""
MODE=download
IFACE=""
LOGFILE=/tmp/traffic-burner.log
CHECK_ONLY=0
TICK=${TICK:-3}              # 目标/停止 检查间隔(秒)
MAXTIME=${MAXTIME:-600}      # 单次请求最长时长(秒)
UP_CHUNK_MB=${UP_CHUNK_MB:-64}  # upload 模式每块大小(MB)

PIDFILE=/tmp/traffic-burner.pid
STOPFLAG=/tmp/traffic-burner.stop

# 注: Cloudflare __down 单次请求有上限(约 50MB, 超过会 403), 故用 bytes=50000000
DEFAULT_URLS="\
https://speed.cloudflare.com/__down?bytes=50000000
https://fsn1-speed.hetzner.com/100MB.bin
https://ash-speed.hetzner.com/100MB.bin
https://speedtest.tokyo2.linode.com/100MB-tokyo2.bin
https://speedtest.singapore.linode.com/100MB-singapore.bin
https://proof.ovh.net/files/100Mb.dat"

# --------------------------------------------------------------- 基础工具 ---
logf() {
  _ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf '%s %s\n' "$_ts" "$*"
  printf '%s %s\n' "$_ts" "$*" >> "$LOGFILE"
}

usage() {
  cat <<'EOF'
traffic-burner.sh — 消耗本机流量的跨发行版脚本 (Debian/Ubuntu/Alpine)

用法: traffic-burner.sh [选项]
  -d 秒     运行时长, 0=不限 (默认 3600)
  -t MB     目标流量 MB(十进制), 0=不限 (默认 0), 达到即停
  -w n      并发数 (默认 2)
  -r 速率   每并发限速, 如 50M / 800k; 默认不限
  -u 列表   URL 列表(逗号或空格分隔), 覆盖内置默认源
  -f 文件   从文件读 URL (每行一条, # 注释)
  -m 模式   download|upload (默认 download; upload 需目标可接收 POST/PUT)
  -i 网卡   统计网卡 (默认自动检测默认路由网卡)
  -l 文件   日志文件 (默认 /tmp/traffic-burner.log)
  -c        只做平台自检, 不跑
  -h        显示本帮助

示例:
  ./traffic-burner.sh -d 3600 -w 4
  ./traffic-burner.sh -t 500 -r 20M
  ./traffic-burner.sh -m upload -u "http://你另一台机/up"
EOF
}

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

netdev_bytes() { # $1=iface $2=rx|tx
  awk -v ifc="$1" -v dir="$2" '{n=$1; sub(/:$/,"",n)} n==ifc { if (dir=="rx") print $2; else print $10; exit }' /proc/net/dev
}
nbytes() {
  _v=$(netdev_bytes "$1" "$2")
  case "$_v" in ''|*[!0-9]*) _v=0 ;; esac
  printf '%s' "$_v"
}
human() {
  awk -v b="$1" 'BEGIN{b=b+0; if (b>=1000000000) printf "%.2f GB", b/1000000000; else printf "%.1f MB", b/1000000}'
}
mbps() {
  awk -v b="$1" -v s="$2" 'BEGIN{if (s<=0) s=1; printf "%.2f", b*8/s/1000000}'
}

# --------------------------------------------------------------- 平台探测 ---
detect_os() {
  OS_ID=unknown; OS_PRETTY=""
  if [ -r /etc/os-release ]; then
    OS_ID=$(awk -F= '/^ID=/{sub(/^[^=]*=/,""); gsub(/"/,""); print; exit}' /etc/os-release)
    OS_PRETTY=$(awk -F= '/^PRETTY_NAME=/{sub(/^[^=]*=/,""); gsub(/"/,""); print; exit}' /etc/os-release)
  fi
  [ -n "$OS_ID" ] || OS_ID=unknown
}
detect_pkg() {
  if command -v apk >/dev/null 2>&1; then PKG=apk
  elif command -v apt-get >/dev/null 2>&1; then PKG=apt
  else PKG=unknown; fi
}
detect_init() {
  if command -v systemctl >/dev/null 2>&1 && { [ -d /run/systemd/system ] || [ "$(cat /proc/1/comm 2>/dev/null)" = systemd ]; }; then
    INIT=systemd
  elif [ "${OS_ID:-}" = alpine ] || command -v rc-service >/dev/null 2>&1 || command -v openrc-run >/dev/null 2>&1; then
    INIT=openrc
  else
    INIT=unknown
  fi
}
detect_iface() {
  _if=$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)
  if [ -z "$_if" ]; then
    _if=$(awk -F: 'NR>2{gsub(/ /,"",$1); if ($1!="" && $1!="lo"){print $1; exit}}' /proc/net/dev)
  fi
  printf '%s' "$_if"
}

ensure_curl() {
  command -v curl >/dev/null 2>&1 && return 0
  logf "curl 缺失, 尝试自动安装 (包管理器: ${PKG})..."
  [ "$(id -u 2>/dev/null)" = "0" ] || { logf "非 root 无法自动安装, 请先手动装 curl"; return 1; }
  case "$PKG" in
    apk)
      apk add --no-cache curl ca-certificates || { logf "apk 安装失败"; return 1; }
      update-ca-certificates >/dev/null 2>&1 || true
      ;;
    apt)
      apt-get update || { logf "apt-get update 失败"; return 1; }
      apt-get install -y --no-install-recommends curl ca-certificates || { logf "apt 安装失败"; return 1; }
      ;;
    *)
      logf "未识别的包管理器, 请手动安装 curl"; return 1 ;;
  esac
  command -v curl >/dev/null 2>&1 || { logf "安装后仍找不到 curl"; return 1; }
  logf "curl 就绪: $(curl --version 2>/dev/null | head -1)"
}

do_check() {
  printf 'OS         : %s (ID=%s)\n' "${OS_PRETTY:-unknown}" "${OS_ID:-unknown}"
  printf '包管理器   : %s\n' "$PKG"
  printf 'init       : %s\n' "$INIT"
  if command -v curl >/dev/null 2>&1; then
    printf 'curl       : %s (%s)\n' "$(command -v curl)" "$(curl --version 2>/dev/null | head -1 | awk '{print $2}')"
  else
    printf 'curl       : 缺失 (运行时将自动安装)\n'
  fi
  printf '网卡(统计) : %s\n' "$IFACE"
  printf 'shell      : sh -> %s\n' "$(readlink -f /bin/sh 2>/dev/null || echo '?')"
  printf 'netdev探测 : rx=%s tx=%s (当前累计字节)\n' "$(nbytes "$IFACE" rx)" "$(nbytes "$IFACE" tx)"
}

# ------------------------------------------------------------------- 工作 ---
fetch() { # $1=url; 结果放全局 _rc
  _cpid=""
  if [ "$MODE" = upload ]; then
    dd if=/dev/zero bs=1048576 count="$UP_CHUNK_MB" 2>/dev/null | \
      curl -fsS --connect-timeout 10 --max-time "$MAXTIME" $RATEOPT \
           -X POST --data-binary @- -H 'Content-Type: application/octet-stream' \
           -o /dev/null "$1" 2>>"$LOGFILE" &
  else
    curl -fsS -L --connect-timeout 10 --max-time "$MAXTIME" $RATEOPT \
         -o /dev/null "$1" 2>>"$LOGFILE" &
  fi
  _cpid=$!
  wait "$_cpid"; _rc=$?
  _cpid=""
}

worker() { # $1=worker id
  _wid="$1"
  trap 'if [ -n "${_cpid:-}" ]; then kill "$_cpid" 2>/dev/null; fi; exit 0' TERM INT HUP
  while :; do
    for _u in $URLS; do
      [ -e "$STOPFLAG" ] && exit 0
      fetch "$_u"
      if [ "$_rc" -ne 0 ] && [ ! -e "$STOPFLAG" ]; then
        logf "worker${_wid}: 请求失败 rc=${_rc} (${_u}), 2 秒后继续"
        sleep 2
      fi
    done
  done
}

# --------------------------------------------------------------- 参数解析 ---
while getopts "d:t:w:r:u:f:m:i:l:ch" opt; do
  case "$opt" in
    d) DURATION=$OPTARG ;;
    t) TARGET_MB=$OPTARG ;;
    w) WORKERS=$OPTARG ;;
    r) RATE=$OPTARG ;;
    u) URLS=$OPTARG ;;
    f) URLS_FILE=$OPTARG ;;
    m) MODE=$OPTARG ;;
    i) IFACE=$OPTARG ;;
    l) LOGFILE=$OPTARG ;;
    c) CHECK_ONLY=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

is_num "$DURATION"  || { echo "-d 需为非负整数(秒)"; exit 2; }
is_num "$TARGET_MB" || { echo "-t 需为非负整数(MB)"; exit 2; }
is_num "$WORKERS"   || { echo "-w 需为正整数"; exit 2; }
[ "$WORKERS" -ge 1 ] || { echo "-w 至少为 1"; exit 2; }
case "$MODE" in download|upload) : ;; *) echo "-m 只能是 download 或 upload"; exit 2 ;; esac

if [ -n "$URLS" ]; then
  URLS=$(printf '%s' "$URLS" | tr ',' ' ')
else
  URLS=$DEFAULT_URLS
fi
if [ -n "$URLS_FILE" ]; then
  [ -r "$URLS_FILE" ] || { echo "URL 文件不可读: $URLS_FILE"; exit 1; }
  URLS="$URLS $(awk '!/^[ \t]*#/ && NF' "$URLS_FILE" | tr '\n' ' ')"
fi

RATEOPT=""
if [ -n "$RATE" ] && [ "$RATE" != "0" ]; then RATEOPT="--limit-rate $RATE"; fi

detect_os; detect_pkg; detect_init
[ -n "$IFACE" ] || IFACE=$(detect_iface)
[ -n "$IFACE" ] || { echo "无法自动识别网卡, 请用 -i 指定"; exit 1; }

if [ "$CHECK_ONLY" = 1 ]; then do_check; exit 0; fi

ensure_curl || exit 1
: >> "$LOGFILE" || { echo "无法写入日志: $LOGFILE"; exit 1; }

if [ -f "$PIDFILE" ]; then
  _old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "${_old:-}" ] && kill -0 "$_old" 2>/dev/null; then
    echo "已有实例在运行 (pid $_old); 停止它或删除 $PIDFILE 后重试"; exit 1
  fi
fi
printf '%s\n' "$$" > "$PIDFILE"
rm -f "$STOPFLAG"

stopped=0; WPIDS=""
on_signal() {
  stopped=1
  : > "$STOPFLAG"
  for _p in $WPIDS; do kill "$_p" 2>/dev/null || :; done
}
trap on_signal INT TERM HUP

# --------------------------------------------------------------- 启动 ------
logf "================================================================="
logf "traffic-burner v1.0 启动 | OS: ${OS_PRETTY:-$OS_ID} | 模式: $MODE | 并发: $WORKERS"
if [ "$DURATION" -gt 0 ]; then _d="${DURATION}s"; else _d="不限(手动停止)"; fi
if [ "$TARGET_MB" -gt 0 ]; then _t="${TARGET_MB} MB"; else _t="不限"; fi
logf "时长: $_d | 目标: $_t | 限速: ${RATE:-不限}"
logf "网卡: $IFACE | 日志: $LOGFILE"
logf "URL: $(printf '%s' "$URLS" | tr '\n' ' ' | awk '{print substr($0,1,160)}')"

START_TS=$(date +%s)
RX0=$(nbytes "$IFACE" rx); TX0=$(nbytes "$IFACE" tx)

_i=1
while [ "$_i" -le "$WORKERS" ]; do
  worker "$_i" &
  WPIDS="$WPIDS $!"
  _i=$((_i+1))
done

# --------------------------------------------------------------- 主循环 ----
ticks=0; REASON=""
while :; do
  sleep "$TICK"
  if [ "$stopped" = 1 ]; then REASON="收到停止信号"; break; fi
  now=$(date +%s); el=$((now - START_TS))
  if [ "$DURATION" -gt 0 ] && [ "$el" -ge "$DURATION" ]; then REASON="时长结束"; break; fi
  cur_rx=$(( $(nbytes "$IFACE" rx) - RX0 ))
  cur_tx=$(( $(nbytes "$IFACE" tx) - TX0 ))
  if [ "$MODE" = upload ]; then cur=$cur_tx; else cur=$cur_rx; fi
  if [ "$TARGET_MB" -gt 0 ] && [ "$cur" -ge $((TARGET_MB * 1000000)) ]; then REASON="达到目标流量"; break; fi
  ticks=$((ticks+1))
  if [ $((ticks % 10)) -eq 0 ]; then
    logf "进行中 ${el}s | RX $(human "$cur_rx") | TX $(human "$cur_tx") | 均速 $(mbps "$cur" "$el") Mbps"
  fi
done

# --------------------------------------------------------------- 收尾 ------
: > "$STOPFLAG"
for _p in $WPIDS; do kill "$_p" 2>/dev/null || :; done
wait 2>/dev/null || :

END_TS=$(date +%s); EL=$((END_TS - START_TS)); [ "$EL" -le 0 ] && EL=1
RX1=$(nbytes "$IFACE" rx); TX1=$(nbytes "$IFACE" tx)
RX=$((RX1 - RX0)); TX=$((TX1 - TX0))

logf "===================== 汇总 ($REASON) ====================="
logf "运行: ${EL}s | 网卡: $IFACE | 模式: $MODE | 并发: $WORKERS"
logf "RX 下行: $(human "$RX")  |  平均 $(mbps "$RX" "$EL") Mbps"
logf "TX 上行: $(human "$TX")  |  平均 $(mbps "$TX" "$EL") Mbps"
if [ "$TARGET_MB" -gt 0 ]; then
  if [ "$MODE" = upload ]; then _fin=$TX; else _fin=$RX; fi
  logf "目标 ${TARGET_MB} MB ($MODE 方向): 实际 $(human "$_fin")"
fi
logf "================================================================="

rm -f "$PIDFILE" "$STOPFLAG"
exit 0
