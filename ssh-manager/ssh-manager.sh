#!/bin/sh
#=============================================================
#  ssh-manager.sh — 交互式 SSH 配置管理脚本
#  适用系统: Debian / Ubuntu / Alpine Linux
#  功能:
#    1. 查看 SSH 状态
#    2. 开启/关闭 密码登录
#    3. 修改 SSH 端口
#    4. 开启/关闭 密钥登录 (PubkeyAuthentication)
#    5. 导入公钥
#    6. 查看/删除 公钥
#    7. 修改公钥
#    8. 重启 SSH 服务
#    9. 设置开机自启
#  用法: sudo sh ssh-manager.sh
#  可选环境变量:
#    SSH_CONFIG=/path/sshd_config   指定配置文件(测试用)
#    SSH_BACKUP_DIR=/path           指定备份目录
#    SSH_MANAGER_NO_RESTART=1       只改配置、不重启服务(测试用)
#=============================================================

set -u

CONFIG="${SSH_CONFIG:-/etc/ssh/sshd_config}"
CONFIG_DIR=$(dirname "$CONFIG")
DROPIN_DIR="$CONFIG_DIR/sshd_config.d"
BACKUP_ROOT="${SSH_BACKUP_DIR:-$CONFIG_DIR/ssh-manager-backups}"
SKIP_RESTART="${SSH_MANAGER_NO_RESTART:-}"

OS_NAME=""
OS_VER=""
SSHD_BIN=""
SSH_KEYGEN=""
LAST_BACKUP=""

#---------------------- 输出 ----------------------
if [ -t 2 ]; then
  C_RED=$(printf '\033[31m');   C_GREEN=$(printf '\033[32m')
  C_YELLOW=$(printf '\033[33m'); C_BLUE=$(printf '\033[36m')
  C_BOLD=$(printf '\033[1m');   C_NC=$(printf '\033[0m')
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_NC=''
fi

msg()  { printf '%s\n' "$*"; }
line() { printf '%s\n' "------------------------------------------------------------"; }
info() { printf '%s[信息]%s %s\n' "$C_BLUE" "$C_NC" "$*" >&2; }
ok()   { printf '%s[成功]%s %s\n' "$C_GREEN" "$C_NC" "$*" >&2; }
warn() { printf '%s[警告]%s %s\n' "$C_YELLOW" "$C_NC" "$*" >&2; }
err()  { printf '%s[错误]%s %s\n' "$C_RED" "$C_NC" "$*" >&2; }
die()  { err "$*"; exit 1; }

tmpfile() { mktemp "${TMPDIR:-/tmp}/ssh-manager.XXXXXX"; }

#---------------------- 交互 ----------------------
# 读取输入(带默认值)。提示写到 stderr，结果写 stdout，可安全用于 $(...)。
ask() {
  _msg=$1; _def=${2:-}
  if [ -n "$_def" ]; then printf '%s [%s]: ' "$_msg" "$_def" >&2
  else printf '%s: ' "$_msg" >&2; fi
  IFS= read -r _ans || _ans=""
  [ -z "$_ans" ] && _ans=$_def
  printf '%s' "$_ans"
}

confirm() {
  _msg=$1; _def=${2:-n}
  if [ "$_def" = y ]; then _hint='Y/n'; else _hint='y/N'; fi
  printf '%s [%s]: ' "$_msg" "$_hint" >&2
  IFS= read -r _ans || _ans=""
  [ -z "$_ans" ] && _ans=$_def
  case "$_ans" in y|Y|yes|YES|Yes) return 0;; *) return 1;; esac
}

pause() { printf '按回车键继续...' >&2; IFS= read -r _x || true; }

#---------------------- 环境检测 ----------------------
detect_os() {
  if [ -f /etc/alpine-release ]; then
    OS_NAME="Alpine Linux"
    OS_VER=$(cat /etc/alpine-release)
  elif [ -r /etc/os-release ]; then
    OS_NAME=$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}" )
    OS_VER=$( . /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-}" )
  else
    OS_NAME=$(uname -s); OS_VER=$(uname -r)
  fi
}

find_sshd() {
  SSHD_BIN=$(command -v sshd 2>/dev/null || true)
  if [ -z "$SSHD_BIN" ]; then
    for _p in /usr/sbin/sshd /usr/local/sbin/sshd /sbin/sshd; do
      [ -x "$_p" ] && SSHD_BIN=$_p && break
    done
  fi
  SSH_KEYGEN=$(command -v ssh-keygen 2>/dev/null || true)
}

is_alpine() { [ -f /etc/alpine-release ]; }

ssh_unit() {
  if command -v rc-service >/dev/null 2>&1 && [ -d /etc/init.d ]; then
    printf 'sshd'
  elif command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
      printf 'sshd'
    else
      printf 'ssh'
    fi
  else
    printf 'ssh'
  fi
}

ssh_running() {
  if command -v rc-service >/dev/null 2>&1 && [ -d /etc/init.d ]; then
    rc-service sshd status >/dev/null 2>&1
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet "$(ssh_unit)" 2>/dev/null
  elif command -v pgrep >/dev/null 2>&1; then
    pgrep -x sshd >/dev/null 2>&1
  else
    ps w 2>/dev/null | grep -q '[s]shd'
  fi
}

restart_ssh() {
  if [ -n "$SKIP_RESTART" ]; then
    warn "测试模式(SSH_MANAGER_NO_RESTART)：跳过服务重启"
    return 0
  fi
  if command -v rc-service >/dev/null 2>&1 && [ -d /etc/init.d ]; then
    info "执行: rc-service sshd restart"
    rc-service sshd restart
  elif command -v systemctl >/dev/null 2>&1; then
    _u=$(ssh_unit)
    info "执行: systemctl restart $_u"
    systemctl restart "$_u"
  elif command -v service >/dev/null 2>&1; then
    info "执行: service ssh restart"
    service ssh restart 2>/dev/null || service sshd restart
  else
    err "未找到可用的服务管理工具(systemctl / rc-service / service)"
    return 1
  fi
}

enable_ssh() {
  if command -v rc-update >/dev/null 2>&1 && [ -d /etc/init.d ]; then
    rc-update add sshd default
    rc-service sshd start
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl enable "$(ssh_unit)" 2>/dev/null
    systemctl start "$(ssh_unit)" 2>/dev/null
  else
    err "未找到开机自启管理工具"
    return 1
  fi
}

# 首次安装/全新系统可能还没有主机密钥，sshd -t/-T 会直接报错，这里补齐
ensure_host_keys() {
  [ -n "$SSH_KEYGEN" ] || return 0
  [ -f "$CONFIG" ] || return 0
  [ -w "$CONFIG_DIR" ] || return 0
  for _k in "$CONFIG_DIR"/ssh_host_*_key; do
    [ -f "$_k" ] && return 0
  done
  info "未找到 SSH 主机密钥，正在生成(ssh-keygen -A)..."
  "$SSH_KEYGEN" -A >/dev/null 2>&1 || warn "主机密钥生成失败，请手动运行 ssh-keygen -A"
}

install_openssh() {
  if is_alpine; then
    apk add --no-cache openssh
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
  else
    err "请手动安装 OpenSSH Server"
    return 1
  fi
}

#---------------------- 配置读写 ----------------------
validate_config() {
  if [ ! -x "$SSHD_BIN" ]; then
    warn "未找到 sshd 可执行文件，跳过语法校验"
    return 0
  fi
  _out=$("$SSHD_BIN" -t -f "$CONFIG" 2>&1)
  if [ $? -ne 0 ]; then
    err "sshd 配置语法校验失败："
    printf '%s\n' "$_out" >&2
    return 1
  fi
  return 0
}

# 取某项生效值(如 passwordauthentication)，来自 sshd -T
effective() {
  [ -x "$SSHD_BIN" ] || { printf ''; return 0; }
  "$SSHD_BIN" -T -f "$CONFIG" 2>/dev/null \
    | awk -v k="$1" 'tolower($1)==tolower(k){print $2; exit}'
}

effective_ports() {
  [ -x "$SSHD_BIN" ] || { printf ''; return 0; }
  "$SSHD_BIN" -T -f "$CONFIG" 2>/dev/null \
    | awk 'tolower($1)=="port"{printf "%s ", $2}'
}

# 在单个文件中设置指令：替换所有全局出现处(保留 Match 块内的条件配置)，
# 若不存在则在首个 Match 块之前插入，否则追加到文件末尾。
set_in_file() {
  _file=$1; _key=$2; _val=$3
  [ -f "$_file" ] || return 1
  _tmp=$(tmpfile) || return 1
  awk -v key="$_key" -v val="$_val" '
    function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
    BEGIN { lk = tolower(key); printed = 0; inmatch = 0 }
    {
      low = tolower($0)
      ismatch = (low ~ /^[ \t]*match([ \t]|$)/)
      if (ismatch && !inmatch) {
        inmatch = 1
        if (!printed) { print key " " val; printed = 1 }
      }
      if (!inmatch) {
        t = ltrim(low)
        if (t ~ ("^" lk "([ \t]|$)")) {
          if (!printed) { print key " " val; printed = 1 }
          next
        }
      }
      print
    }
    END { if (!printed) print key " " val }
  ' "$_file" > "$_tmp" || { rm -f "$_tmp"; return 1; }
  cat "$_tmp" > "$_file" || { rm -f "$_tmp"; return 1; }
  rm -f "$_tmp"
  return 0
}

# 同时更新主配置和 sshd_config.d/ 下的覆盖文件，避免被 drop-in 抢先覆盖
set_directive() {
  _key=$1; _val=$2
  set_in_file "$CONFIG" "$_key" "$_val" || { err "写入 $CONFIG 失败"; return 1; }
  if [ -d "$DROPIN_DIR" ]; then
    for _f in "$DROPIN_DIR"/*.conf; do
      [ -f "$_f" ] || continue
      if grep -qiE "^[[:space:]]*$_key([[:space:]]|$)" "$_f"; then
        set_in_file "$_f" "$_key" "$_val" || return 1
        info "已同步更新: $_f"
      fi
    done
  fi
  return 0
}

#---------------------- 备份 / 回滚 ----------------------
make_backup() {
  _ts=$(date +%Y%m%d-%H%M%S)-$$
  _dest="$BACKUP_ROOT/$_ts"
  mkdir -p "$_dest" || { err "无法创建备份目录: $_dest"; return 1; }
  cp -p "$CONFIG" "$_dest/sshd_config" || { err "备份 $CONFIG 失败"; return 1; }
  if [ -d "$DROPIN_DIR" ]; then
    mkdir -p "$_dest/sshd_config.d"
    for _f in "$DROPIN_DIR"/*.conf; do
      [ -f "$_f" ] || continue
      cp -p "$_f" "$_dest/sshd_config.d/" 2>/dev/null
    done
  fi
  LAST_BACKUP=$_dest
  info "已备份配置到: $_dest"
  return 0
}

restore_backup() {
  [ -n "$LAST_BACKUP" ] || return 1
  [ -f "$LAST_BACKUP/sshd_config" ] || return 1
  cp -p "$LAST_BACKUP/sshd_config" "$CONFIG" || return 1
  if [ -d "$LAST_BACKUP/sshd_config.d" ] && [ -d "$DROPIN_DIR" ]; then
    for _f in "$LAST_BACKUP/sshd_config.d"/*.conf; do
      [ -f "$_f" ] || continue
      cp -p "$_f" "$DROPIN_DIR/$(basename "$_f")" || return 1
    done
  fi
  ok "配置已回滚到修改前"
  return 0
}

backup_file_simple() {
  _f=$1
  [ -f "$_f" ] || return 0
  mkdir -p "$BACKUP_ROOT" 2>/dev/null || return 0
  _b="$BACKUP_ROOT/$(basename "$_f").$(date +%Y%m%d-%H%M%S)-$$.bak"
  cp -p "$_f" "$_b" && info "已备份: $_b"
}

# 校验 + 重启；失败自动回滚
apply_change() {
  if ! validate_config; then
    err "配置校验未通过，正在回滚..."
    restore_backup
    return 1
  fi
  if ! restart_ssh; then
    err "SSH 服务重启失败，正在回滚..."
    restore_backup
    restart_ssh >/dev/null 2>&1
    return 1
  fi
  ok "SSH 配置已生效"
  return 0
}

#---------------------- 公钥工具 ----------------------
# 从一行(可含 options)中取出 "<type> <base64>"
extract_key_blob() {
  printf '%s\n' "$1" | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^(ssh-|ecdsa-|sk-)/) { print $i " " $(i+1); exit }
    }
  }'
}

key_fp() {
  _k=$1
  [ -n "$SSH_KEYGEN" ] || { printf ''; return 0; }
  _t=$(tmpfile) || { printf ''; return 0; }
  printf '%s\n' "$_k" > "$_t"
  "$SSH_KEYGEN" -lf "$_t" 2>/dev/null | awk '{print $2}'
  rm -f "$_t"
}

valid_key() {
  _line=$1
  _kb=$(extract_key_blob "$_line")
  [ -n "$_kb" ] || return 1
  case "$_kb" in
    ssh-*\ *|ecdsa-*\ *|sk-*\ *) ;;
    *) return 1;;
  esac
  if [ -n "$SSH_KEYGEN" ]; then
    _t=$(tmpfile) || return 1
    printf '%s\n' "$_kb" > "$_t"
    "$SSH_KEYGEN" -lf "$_t" >/dev/null 2>&1
    _r=$?
    rm -f "$_t"
    return $_r
  fi
  return 0
}

key_exists() {
  _f=$1; _k=$2
  _kb=$(extract_key_blob "$_k")
  [ -n "$_kb" ] || return 1
  awk -v want="$_kb" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^(ssh-|ecdsa-|sk-)/) { if ($i " " $(i+1) == want) { found = 1 } ; break }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$_f"
}

# 仅修改注释，保留 options 与 key 本身
rewrite_comment() {
  awk -v c="$1" '{
    pre = ""
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^(ssh-|ecdsa-|sk-)/) {
        printf "%s%s %s", pre, $i, $(i+1)
        if (c != "") printf " %s", c
        printf "\n"
        exit
      }
      pre = pre $i " "
    }
  }'
}

#---------------------- 用户与文件 ----------------------
choose_user() {
  printf '系统中可登录用户: root' >&2
  for _u in $(awk -F: '$3>=1000 && $7 !~ /(nologin|false)$/ {print $1}' /etc/passwd); do
    printf ' %s' "$_u" >&2
  done
  printf '\n' >&2
  _u=$(ask "目标用户" "root")
  case "$_u" in
    *[!a-zA-Z0-9._-]*|'') err "非法用户名"; return 1;;
  esac
  grep -q "^$_u:" /etc/passwd || { err "用户不存在: $_u"; return 1; }
  printf '%s' "$_u"
}

user_home() { awk -F: -v u="$1" '$1==u {print $6; exit}' /etc/passwd; }
keys_file() { printf '%s/.ssh/authorized_keys' "$(user_home "$1")"; }

# 准备 .ssh 目录与 authorized_keys，返回其路径
prepare_keys() {
  _u=$1
  _home=$(user_home "$_u")
  if [ -z "$_home" ] || [ ! -d "$_home" ]; then
    err "用户主目录不存在: $_home"
    return 1
  fi
  mkdir -p "$_home/.ssh" || return 1
  [ -f "$_home/.ssh/authorized_keys" ] || : > "$_home/.ssh/authorized_keys"
  chmod 700 "$_home/.ssh"
  chmod 600 "$_home/.ssh/authorized_keys"
  chown -R "$_u":"$(id -gn "$_u" 2>/dev/null)" "$_home/.ssh" 2>/dev/null \
    || warn "无法设置 $_home/.ssh 的属主(请检查)" >&2
  _m=$(stat -c %a "$_home" 2>/dev/null || true)
  case "$_m" in
    ''|*[!0-7]*) ;;
    *) [ $(( 0$_m & 0022 )) -ne 0 ] \
         && warn "主目录 $_home 权限 $_m 允许组/其他用户写入，StrictModes 可能拒绝密钥登录" >&2 ;;
  esac
  _akf=$(effective authorizedkeysfile)
  case "$_akf" in
    *authorized_keys*) ;;
    '') ;;
    *) warn "当前 AuthorizedKeysFile=$_akf，写入 $_home/.ssh/authorized_keys 可能不生效" >&2 ;;
  esac
  printf '%s' "$_home/.ssh/authorized_keys"
}

list_keys_file() {
  _f=$1
  if [ ! -s "$_f" ]; then msg "(暂无公钥)"; return 0; fi
  _i=0; _l=""
  while IFS= read -r _l || [ -n "$_l" ]; do
    _i=$((_i + 1))
    case "$_l" in
      ''|'#'*) printf '%3d) %s\n' "$_i" "$_l"; continue;;
    esac
    set -f
    set -- $_l
    set +f
    _type=${1:-?}
    _blob=${2:-}
    _fp=""
    [ -n "$_blob" ] && _fp=$(key_fp "$(extract_key_blob "$_l")")
    _comment=${_l#"$_type $_blob"}
    _comment=${_comment# }
    printf '%3d) %-20s %s  %s\n' "$_i" "$_type" "${_fp:-$_blob}" "$_comment"
  done < "$_f"
}

count_lines() { awk 'END{print NR+0}' "$1"; }

#---------------------- 功能: 状态 ----------------------
show_status() {
  line
  msg "系统      : ${OS_NAME} ${OS_VER}"
  msg "配置文件  : ${CONFIG}"
  msg "sshd 程序 : ${SSHD_BIN:-未找到}"
  if ssh_running; then ok "服务状态  : 运行中"; else warn "服务状态  : 未运行"; fi
  _ports=$(effective_ports)
  msg "监听端口  : ${_ports:-未知}"
  msg "密码登录  : $(effective passwordauthentication)"
  msg "密钥登录  : $(effective pubkeyauthentication)"
  msg "Root 登录 : $(effective permitrootlogin)"
  msg "键盘交互  : $(effective kbdinteractiveauthentication)"
  for _h in /root $(ls -d /home/* 2>/dev/null); do
    [ -f "$_h/.ssh/authorized_keys" ] || continue
    _n=$(grep -cE '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$_h/.ssh/authorized_keys" 2>/dev/null)
    msg "公钥数量  : $_h 共 ${_n:-0} 条"
  done
  line
}

#---------------------- 功能: 密码登录 ----------------------
toggle_password() {
  _cur=$(effective passwordauthentication)
  msg "当前密码登录: ${_cur:-未知}"
  msg "  1) 开启密码登录"
  msg "  2) 关闭密码登录(仅允许密钥)"
  msg "  0) 返回"
  _c=$(ask "请选择" "0")
  case "$_c" in
    1)
      make_backup || return
      set_directive PasswordAuthentication yes || { restore_backup; return; }
      _prl=$(effective permitrootlogin)
      case "$_prl" in
        no|without-password|prohibit-password|forced-commands-only)
          warn "当前 PermitRootLogin=$_prl，root 仍无法用密码登录。"
          if confirm "是否同时改为 PermitRootLogin yes(允许 root 密码登录)?" n; then
            set_directive PermitRootLogin yes
          fi;;
      esac
      apply_change;;
    2)
      _pk=$(effective pubkeyauthentication)
      if [ "$_pk" != yes ]; then
        warn "密钥登录当前是关闭状态，关闭密码登录后将无法远程登录！"
        confirm "仍要关闭密码登录?" n || return
      fi
      make_backup || return
      set_directive PasswordAuthentication no || { restore_backup; return; }
      _kbd=$(effective kbdinteractiveauthentication)
      if [ "$_kbd" = yes ]; then
        warn "KbdInteractiveAuthentication=yes，PAM 仍可能允许密码登录。"
        if confirm "是否一并关闭 KbdInteractiveAuthentication?" y; then
          set_directive KbdInteractiveAuthentication no
        fi
      fi
      apply_change;;
    *) return;;
  esac
}

#---------------------- 功能: 端口 ----------------------
port_in_use() {
  _p=$1
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | awk -v p="$_p" 'NR>1{ n=split($4,a,":"); if (a[n]==p) f=1 } END{ exit(f?0:1) }'
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk -v p="$_p" '$4 ~ (":" p "$") { f=1 } END{ exit(f?0:1) }'
  else
    return 1
  fi
}

show_port_owner() {
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | awk -v p="$1" 'NR>1{ n=split($4,a,":"); if (a[n]==p) print "    "$0 }'
  fi
}

firewall_hint() {
  _p=$1
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    info "检测到 ufw，可执行: ufw allow $_p/tcp"
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    info "检测到 firewalld，可执行: firewall-cmd --permanent --add-port=$_p/tcp && firewall-cmd --reload"
  fi
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = Enforcing ]; then
    info "SELinux 已启用，可执行: semanage port -a -t ssh_port_t -p tcp $_p"
  fi
  info "云服务器请在控制台安全组放行 TCP $_p"
}

change_port() {
  _ports=$(effective_ports)
  msg "当前端口: ${_ports:-未知(默认 22)}"
  _new=$(ask "新端口 (1-65535，0 取消)" "0")
  [ "$_new" = 0 ] && return
  case "$_new" in ''|*[!0-9]*) err "端口必须是数字"; return;; esac
  [ "$_new" -ge 1 ] && [ "$_new" -le 65535 ] || { err "端口范围 1-65535"; return; }
  case " $_ports " in *" $_new "*) warn "配置中已包含该端口"; return;; esac

  if port_in_use "$_new"; then
    warn "端口 $_new 已被占用:"
    show_port_owner "$_new"
    confirm "仍要继续?" n || return
  fi
  warn "修改端口后，新连接必须使用新端口；请先放行防火墙并保留当前会话。"
  confirm "确认修改 SSH 端口?" y || return

  make_backup || return
  set_directive Port "$_new" || { restore_backup; return; }
  if apply_change; then
    ok "SSH 端口已改为 $_new"
    firewall_hint "$_new"
  fi
}

#---------------------- 功能: 密钥登录开关 ----------------------
toggle_pubkey() {
  _cur=$(effective pubkeyauthentication)
  msg "当前密钥登录: ${_cur:-未知}"
  msg "  1) 开启密钥登录"
  msg "  2) 关闭密钥登录"
  msg "  0) 返回"
  _c=$(ask "请选择" "0")
  case "$_c" in
    1)
      make_backup || return
      set_directive PubkeyAuthentication yes || { restore_backup; return; }
      apply_change;;
    2)
      _pw=$(effective passwordauthentication)
      if [ "$_pw" != yes ]; then
        err "密码登录当前也是关闭状态；若再关闭密钥登录将无法远程登录，已取消"
        return
      fi
      warn "关闭密钥登录后，未开启密码登录将可能无法登录！"
      confirm "确认关闭?" n || return
      make_backup || return
      set_directive PubkeyAuthentication no || { restore_backup; return; }
      apply_change;;
    *) return;;
  esac
}

#---------------------- 功能: 导入公钥 ----------------------
import_key() {
  _u=$(choose_user) || return
  _f=$(prepare_keys "$_u") || return
  [ -n "$_f" ] || return
  backup_file_simple "$_f"
  msg "请粘贴公钥(每行一个，可含多个；直接回车结束):"
  _added=0; _dup=0; _bad=0
  while :; do
    printf '> ' >&2
    IFS= read -r _k || break
    _k=$(printf '%s' "$_k" | tr -d '\r')
    [ -z "$_k" ] && break
    case "$_k" in '#'*) continue;; esac
    if ! valid_key "$_k"; then err "公钥格式无效: $_k"; _bad=$((_bad + 1)); continue; fi
    if key_exists "$_f" "$_k"; then warn "已存在，跳过: $(key_fp "$(extract_key_blob "$_k")")"; _dup=$((_dup + 1)); continue; fi
    if [ -s "$_f" ] && [ -n "$(tail -c 1 "$_f" 2>/dev/null)" ]; then printf '\n' >> "$_f"; fi
    printf '%s\n' "$_k" >> "$_f"
    _added=$((_added + 1))
    ok "已添加: $(key_fp "$(extract_key_blob "$_k")")"
  done
  chmod 600 "$_f"
  chown "$_u":"$(id -gn "$_u" 2>/dev/null)" "$_f" 2>/dev/null
  msg "完成：新增 $_added 条，重复 $_dup 条，无效 $_bad 条"
  msg "当前该用户的公钥："
  list_keys_file "$_f"
}

#---------------------- 功能: 删除公钥 ----------------------
delete_keys() {
  _u=$(choose_user) || return
  _f=$(keys_file "$_u")
  [ -s "$_f" ] || { warn "该用户没有公钥"; return; }
  list_keys_file "$_f"
  _total=$(count_lines "$_f")
  printf '输入要删除的编号(如 1,3 或 2-4 或 all；0 取消): ' >&2
  IFS= read -r _sel || return
  case "$_sel" in ''|0) return;; esac

  _tmp=$(tmpfile) || return
  : > "$_tmp"
  _oldIFS=$IFS; IFS=','
  for _p in $_sel; do
    case "$_p" in
      all|ALL)
        _n=1; while [ "$_n" -le "$_total" ]; do printf '%s\n' "$_n" >> "$_tmp"; _n=$((_n + 1)); done;;
      *-*)
        _a=${_p%-*}; _b=${_p#*-}
        case "$_a$_b" in *[!0-9]*|'') warn "无效: $_p"; continue;; esac
        if [ "$_a" -gt "$_b" ]; then warn "无效范围: $_p"; continue; fi
        _n=$_a
        while [ "$_n" -le "$_b" ]; do
          if [ "$_n" -ge 1 ] && [ "$_n" -le "$_total" ]; then printf '%s\n' "$_n" >> "$_tmp"; fi
          _n=$((_n + 1))
        done;;
      *[!0-9]*) warn "无效: $_p";;
      *) if [ "$_p" -ge 1 ] && [ "$_p" -le "$_total" ]; then printf '%s\n' "$_p" >> "$_tmp"; else warn "超出范围: $_p"; fi;;
    esac
  done
  IFS=$_oldIFS

  _cnt=$(count_lines "$_tmp")
  if [ "$_cnt" -eq 0 ]; then warn "没有选中任何公钥"; rm -f "$_tmp"; return; fi
  confirm "确认删除 $_cnt 条公钥?" y || { rm -f "$_tmp"; return; }

  backup_file_simple "$_f"
  _out=$(tmpfile) || { rm -f "$_tmp"; return; }
  awk -v list="$_tmp" 'BEGIN{ while ((getline n < list) > 0) del[n+0]=1 } !(NR in del)' "$_f" > "$_out"
  cat "$_out" > "$_f"
  rm -f "$_out" "$_tmp"
  chmod 600 "$_f"
  chown "$_u":"$(id -gn "$_u" 2>/dev/null)" "$_f" 2>/dev/null
  ok "已删除 $_cnt 条公钥"
  msg "当前该用户的公钥："
  list_keys_file "$_f"
}

#---------------------- 功能: 修改公钥 ----------------------
modify_key() {
  _u=$(choose_user) || return
  _f=$(keys_file "$_u")
  [ -s "$_f" ] || { warn "该用户没有公钥"; return; }
  list_keys_file "$_f"
  _total=$(count_lines "$_f")
  _n=$(ask "要修改的编号 (0 取消)" "0")
  case "$_n" in ''|0) return;; esac
  case "$_n" in *[!0-9]*) err "无效编号"; return;; esac
  if [ "$_n" -lt 1 ] || [ "$_n" -gt "$_total" ]; then err "编号超出范围"; return; fi

  _line=$(awk -v n="$_n" 'NR==n{print; exit}' "$_f")
  msg "当前内容: $_line"
  msg "  1) 替换整行(粘贴新公钥)"
  msg "  2) 只修改注释"
  msg "  0) 返回"
  _c=$(ask "请选择" "0")
  case "$_c" in
    1)
      printf '粘贴新公钥: ' >&2
      IFS= read -r _new || return
      _new=$(printf '%s' "$_new" | tr -d '\r')
      valid_key "$_new" || { err "公钥格式无效"; return; };;
    2)
      _cm=$(ask "新注释(留空则删除注释)" "")
      _new=$(printf '%s\n' "$_line" | rewrite_comment "$_cm")
      [ -n "$_new" ] || { err "解析失败"; return; };;
    *) return;;
  esac

  backup_file_simple "$_f"
  _out=$(tmpfile) || return
  NEW="$_new" awk -v n="$_n" 'NR==n{print ENVIRON["NEW"]; next} {print}' "$_f" > "$_out"
  cat "$_out" > "$_f"
  rm -f "$_out"
  chmod 600 "$_f"
  chown "$_u":"$(id -gn "$_u" 2>/dev/null)" "$_f" 2>/dev/null
  ok "已修改第 $_n 条公钥"
  msg "当前该用户的公钥："
  list_keys_file "$_f"
}

#---------------------- 功能: 服务 ----------------------
restart_service() {
  if ssh_running; then info "SSH 服务正在运行"; else warn "SSH 服务未运行"; fi
  confirm "重启 SSH 服务?" y || return
  if restart_ssh; then ok "SSH 服务已重启"; else err "SSH 服务重启失败"; fi
}

#---------------------- 主菜单 ----------------------
banner() {
  line
  printf '%s SSH 管理脚本 %s | 系统: %s %s\n' "$C_BOLD" "$C_NC" "$OS_NAME" "$OS_VER"
  printf '%s 配置: %s %s\n' "$C_BOLD" "$CONFIG" "$C_NC"
  line
}

main_menu() {
  while :; do
    banner
    cat <<'EOF'
 1) 查看 SSH 状态
 2) 开启 / 关闭 密码登录
 3) 修改 SSH 端口
 4) 开启 / 关闭 密钥登录
 5) 导入公钥
 6) 查看 / 删除 公钥
 7) 修改公钥
 8) 重启 SSH 服务
 9) 设置开机自启
 0) 退出
EOF
    line
    printf '请选择: ' >&2
    IFS= read -r _choice || break
    case "$_choice" in
      1) show_status; pause;;
      2) toggle_password; pause;;
      3) change_port; pause;;
      4) toggle_pubkey; pause;;
      5) import_key; pause;;
      6) delete_keys; pause;;
      7) modify_key; pause;;
      8) restart_service; pause;;
      9) if enable_ssh; then ok "已设置开机自启"; else err "设置失败"; fi; pause;;
      0|q|Q|exit) break;;
      '') ;;
      *) warn "无效选项: $_choice";;
    esac
  done
}

usage() {
  cat <<'EOF'
用法:
  sudo sh ssh-manager.sh          进入交互式菜单
  sudo sh ssh-manager.sh --status 仅显示当前 SSH 状态
  sudo sh ssh-manager.sh --help   显示本帮助

适用系统: Debian / Ubuntu / Alpine Linux
功能: 密码登录开关 / 端口修改 / 密钥登录开关 / 公钥导入·删除·修改
EOF
}

#---------------------- 初始化 ----------------------
main() {
  detect_os
  find_sshd
  ensure_host_keys

  case "${1:-}" in
    -h|--help) usage; exit 0;;
    --status) show_status; exit 0;;
  esac

  if [ "$(id -u)" -ne 0 ] && [ -z "$SKIP_RESTART" ]; then
    die "请使用 root 运行：sudo sh $0"
  fi

  if [ ! -f "$CONFIG" ]; then
    err "未找到 SSH 配置文件: $CONFIG"
    if confirm "是否安装 OpenSSH Server?" y; then
      install_openssh || die "安装失败，请手动安装 openssh-server"
      find_sshd
      ensure_host_keys
    else
      exit 1
    fi
  fi

  main_menu
  msg "已退出。"
}

main "$@"
