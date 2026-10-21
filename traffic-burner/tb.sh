#!/bin/sh
# ============================================================================
# tb — traffic-burner 交互式控制台 (一键菜单)
#
# 跨发行版: Debian / Ubuntu / Alpine (dash 与 BusyBox ash 通吃)
# 依赖与核心脚本相同: curl 缺失时核心会自动用 apt/apk 安装
#
# 用法:
#   tb              打开交互菜单
#   tb -c           任意参数直接透传给核心 traffic-burner (例: -c 平台自检)
#
# 文件约定: 本脚本与核心 (traffic-burner.sh 或 traffic-burner) 放同一目录,
#           或核心已安装到 PATH。
# ============================================================================
set -u
set -f

PIDFILE=/tmp/traffic-burner.pid
STOPFLAG=/tmp/traffic-burner.stop
LOGFILE=/tmp/traffic-burner.log
OUTFILE=/tmp/traffic-burner.out

# --------------------------------------------------------------- 找到核心 ---
case "$0" in
  */*) _self_dir=${0%/*} ;;
  *)   _self_dir=$(command -v "$0" 2>/dev/null) || _self_dir="."
       _self_dir=${_self_dir%/*} ;;
esac
[ -n "$_self_dir" ] || _self_dir="."
_self_dir=$(CDPATH= cd "$_self_dir" 2>/dev/null && pwd) || _self_dir="."

CORE=""
for _c in "$_self_dir/traffic-burner.sh" "$_self_dir/traffic-burner"; do
  if [ -f "$_c" ]; then CORE=$_c; break; fi
done
if [ -z "$CORE" ]; then
  CORE=$(command -v traffic-burner 2>/dev/null) || CORE=""
fi
if [ -z "$CORE" ]; then
  echo "错误: 找不到核心脚本 traffic-burner(.sh); 请与 tb 放在同一目录, 或安装到 PATH。" >&2
  exit 1
fi

# 参数透传: tb -c / tb -t 500 ...
if [ $# -gt 0 ]; then
  exec sh "$CORE" "$@"
fi

# --------------------------------------------------------------- 颜色/UI ---
if [ -t 1 ]; then
  C_R=$(printf '\033[0m');  C_B=$(printf '\033[1m');  C_G=$(printf '\033[32m')
  C_Y=$(printf '\033[33m'); C_RD=$(printf '\033[31m'); C_C=$(printf '\033[36m')
  C_D=$(printf '\033[2m')
else
  C_R=; C_B=; C_G=; C_Y=; C_RD=; C_C=; C_D=
fi

line() { printf '%s\n' "──────────────────────────────────────────────────"; }

# 读取输入: 结果放 REPLY; $1=提示 $2=默认值(可省)
ask() {
  printf '%s' "$1"
  if [ -n "${2:-}" ]; then printf ' %s[%s]%s' "$C_D" "$2" "$C_R"; fi
  printf ': '
  REPLY=
  IFS= read -r REPLY || REPLY=
  [ -n "$REPLY" ] || REPLY=${2:-}
}

# 数值输入(回车=默认; 非法重问)
ask_num() {
  while :; do
    ask "$1" "$2"
    case "$REPLY" in
      '') return 0 ;;
      *[!0-9]*) printf '  %s请输入数字%s\n' "$C_RD" "$C_R" ;;
      *) return 0 ;;
    esac
  done
}

enter() {
  printf '\n  %s(回车继续)%s ' "$C_D" "$C_R"
  REPLY=; IFS= read -r REPLY || true
}

# --------------------------------------------------------------- 状态工具 ---
running_pid() {
  [ -f "$PIDFILE" ] || return 1
  _rp=$(cat "$PIDFILE" 2>/dev/null)
  case "$_rp" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$_rp" 2>/dev/null || return 1
  printf '%s' "$_rp"
}

state_text() {
  if _sp=$(running_pid); then
    printf '%s运行中%s (pid %s)' "$C_G" "$C_R" "$_sp"
  else
    printf '%s空闲%s' "$C_Y" "$C_R"
  fi
}

start_engine() { # $1 = 传给核心的参数串
  if _sp=$(running_pid); then
    printf '  %s已有实例在运行 (pid %s)%s, 先停止 (菜单 6) 再启动\n' "$C_RD" "$_sp" "$C_R"
    return 1
  fi
  [ -f "$PIDFILE" ] && rm -f "$PIDFILE"
  printf '  启动: %straffic-burner %s%s\n' "$C_B" "$1" "$C_R"
  nohup sh "$CORE" $1 >"$OUTFILE" 2>&1 &
  _bg=$!
  sleep 2
  if ! kill -0 "$_bg" 2>/dev/null; then
    printf '  %s启动失败或立即退出%s, 最近输出:\n' "$C_RD" "$C_R"
    [ -f "$OUTFILE" ] && tail -n 8 "$OUTFILE"
    return 1
  fi
  printf '  %s已后台启动%s (pid %s)\n' "$C_G" "$C_R" "$_bg"
  printf '  日志: %s   (菜单 5=看状态, 6=停止)\n' "$LOGFILE"
  return 0
}

stop_active() {
  if ! _sp=$(running_pid); then
    if [ -f "$PIDFILE" ]; then rm -f "$PIDFILE"; printf '  已清理残留 pid 文件 (进程并不在运行)\n'; fi
    printf '  当前没有运行中的实例\n'
    return 0
  fi
  printf '  停止 pid %s (优雅退出中)...\n' "$_sp"
  kill "$_sp" 2>/dev/null
  _i=0
  while [ "$_i" -lt 15 ] && kill -0 "$_sp" 2>/dev/null; do
    sleep 1
    _i=$((_i+1))
  done
  if kill -0 "$_sp" 2>/dev/null; then
    printf '  %s仍未退出, 强制结束%s\n' "$C_Y" "$C_R"
    kill -9 "$_sp" 2>/dev/null
    rm -f "$PIDFILE" "$STOPFLAG"
  fi
  printf '  %s已停止%s\n' "$C_G" "$C_R"
  if [ -f "$LOGFILE" ]; then
    printf '  最后几行日志:\n'
    tail -n 5 "$LOGFILE" | sed 's/^/    /'
  fi
}

show_status() {
  line
  if _sp=$(running_pid); then
    printf '  %s● 运行中%s  pid=%s\n' "$C_G" "$C_R" "$_sp"
  else
    printf '  ○ 空闲 (没有运行中的实例)\n'
    [ -f "$PIDFILE" ] && rm -f "$PIDFILE"
  fi
  printf '  日志: %s\n' "$LOGFILE"
  line
  if [ -f "$LOGFILE" ]; then
    printf '  %s最近 10 行:%s\n' "$C_D" "$C_R"
    tail -n 10 "$LOGFILE" | sed 's/^/    /'
  else
    printf '  (暂无日志)\n'
  fi
}

launch_confirm() { # $1 = 参数串
  printf '  将执行: %straffic-burner %s%s\n' "$C_B" "$1" "$C_R"
  ask '  确认启动? [Y/n]' 'y'
  case "$REPLY" in
    n|N|no|NO) printf '  已取消\n'; return 0 ;;
  esac
  start_engine "$1"
}

custom_run() {
  line
  printf '%s== 自定义运行 ==%s\n' "$C_B" "$C_R"
  ask "  模式 (1=下载 2=上传)" "1"
  case "$REPLY" in 2) _mode=2 ;; *) _mode=1 ;; esac
  _mflag=; _uflag=
  if [ "$_mode" = 2 ]; then
    _modetxt=上传
    while :; do
      ask "  接收地址 (如 http://目标机:18080/up, 需能接收 POST)" ""
      if [ -n "$REPLY" ]; then
        _url=$(printf '%s' "$REPLY" | tr -d '[:space:]')
        _uflag="-u $_url"
        break
      fi
      printf '  %s上传模式必须填接收地址%s\n' "$C_RD" "$C_R"
    done
    _mflag="-m upload"
  else
    _modetxt=下载
    ask "  下载源列表 (回车=内置默认; 多个用空格或逗号分隔)" ""
    if [ -n "$REPLY" ]; then
      _url=$(printf '%s' "$REPLY" | tr '[:space:]' ',')
      _uflag="-u $_url"
    fi
  fi
  ask_num "  时长秒 (0=不限, 手动停)" "0"
  _dur=$REPLY
  ask_num "  目标流量 MB (0=不限, 达到自动停)" "0"
  _tgt=$REPLY
  if [ "$_dur" = 0 ] && [ "$_tgt" = 0 ]; then
    printf '  %s提示: 时长与目标都不限, 将一直跑到手动停止 (菜单 6)%s\n' "$C_Y" "$C_R"
  fi
  ask_num "  并发数" "2"
  _w=$REPLY
  [ "$_w" -ge 1 ] || _w=2
  ask "  每并发限速 (如 1M / 500k; 回车=不限)" ""
  _rate=
  case "$REPLY" in
    '') ;;
    *[!0-9kKmMgG]*) printf '  %s限速格式不对(示例 1M), 已忽略%s\n' "$C_Y" "$C_R" ;;
    *) _rate="-r $REPLY" ;;
  esac
  _args=$(printf '%s' "$_mflag $_uflag -d $_dur -t $_tgt -w $_w $_rate" | tr -s ' ' | sed 's/^ *//')
  line
  printf '  模式: %s | 时长: %ss | 目标: %sMB | 并发: %s | 限速: %s\n' \
    "$_modetxt" "$_dur" "$_tgt" "$_w" "${_rate#-r }"
  [ -n "$_rate" ] || printf '  (限速: 不限)\n'
  line
  launch_confirm "$_args"
}

help_about() {
  line
  cat <<'EOF'
  用法速览
    tb            打开本菜单
    tb <参数>     直接透传给核心, 例如:
      tb -c                   平台自检
      tb -t 500 -w 4          目标 500MB, 4 并发
      tb -d 3600 -r 10M       1 小时, 每并发限速 10MB/s
      tb -h                   核心脚本完整帮助

  核心参数: -d 时长秒   -t 目标MB   -w 并发数   -r 限速(如 20M)
            -u URL(逗号分隔)  -f URL文件  -m download|upload
            -i 网卡   -l 日志文件   -c 平台自检

  文件:  PID /tmp/traffic-burner.pid   日志 /tmp/traffic-burner.log
  卸载:  install.sh 加 --uninstall 重新执行, 或删除 tb 与 traffic-burner

  提醒:  只消耗自己/授权服务器的流量; 默认源为公共测速节点,
         长期使用请换成自己可控的源。
EOF
}

# --------------------------------------------------------------- 主循环 ------
while :; do
  printf '\n%s' "$C_C"; line; printf '%s' "$C_R"
  printf ' %straffic-burner 控制台%s   状态: %s\n' "$C_B" "$C_R" "$(state_text)"
  printf '%s' "$C_C"; line; printf '%s' "$C_R"
  cat <<'MENU'
  1) 快跑 100 MB       (下载, 2 并发)
  2) 标准 1 GB         (下载, 4 并发)
  3) 挂机 1 小时       (下载, 4 并发, 不限量)
  4) 自定义运行        (下载/上传, 时长/流量/并发/限速)
  5) 查看状态
  6) 停止
  7) 平台自检
  8) 帮助
  0) 退出
MENU
  printf '  选择 [0-8]: '
  if ! IFS= read -r _ch; then printf '\n  (输入结束, 退出)\n'; _ch=0; fi
  case "$_ch" in
    1) launch_confirm "-t 100"; enter ;;
    2) launch_confirm "-t 1000 -w 4"; enter ;;
    3) launch_confirm "-d 3600 -w 4"; enter ;;
    4) custom_run; enter ;;
    5) show_status; enter ;;
    6) stop_active; enter ;;
    7) sh "$CORE" -c; enter ;;
    8) help_about; enter ;;
    0|q|Q|quit|exit)
      if _sp=$(running_pid); then
        printf '\n  %s注意: 实例 (pid %s) 仍在后台运行%s; 下次运行 tb 可管理\n' "$C_Y" "$_sp" "$C_R"
      fi
      printf '  再见\n'
      exit 0 ;;
    *) printf '  %s无效选项: %s%s\n' "$C_RD" "$_ch" "$C_R" ;;
  esac
done
