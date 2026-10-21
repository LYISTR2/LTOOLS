#!/bin/sh
# ============================================================================
# traffic-burner 一键安装脚本 (Debian / Ubuntu / Alpine)
#
# 一行安装:
#   curl -fsSL https://raw.githubusercontent.com/LYISTR2/LTOOLS/main/traffic-burner/install.sh | sh
#   wget -qO-  https://raw.githubusercontent.com/LYISTR2/LTOOLS/main/traffic-burner/install.sh | sh
#
# 附加参数 (管道方式: ... | sh -s -- 参数):
#   --prefix DIR   安装目录 (默认: root → /usr/local/bin, 其他用户 → ~/.local/bin)
#   --no-run       装完不自动进入菜单
#   --uninstall    卸载
#
# 环境变量:
#   TB_BRANCH   分支名 (默认 main)
#   TB_BASE     下载基址 (默认 GitHub raw; 可指向镜像/内网)
# ============================================================================
set -u

REPO="LYISTR2/LTOOLS"
BRANCH=${TB_BRANCH:-main}
BASE=${TB_BASE:-https://raw.githubusercontent.com/$REPO/$BRANCH/traffic-burner}

NORUN=0; UNINSTALL=0; PREFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX=${2:-}; shift 2 ;;
    --no-run) NORUN=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)
      printf '%s\n' \
        "用法: install.sh [--prefix DIR] [--no-run] [--uninstall]" \
        "  --prefix DIR  安装目录 (默认 /usr/local/bin 或 ~/.local/bin)" \
        "  --no-run      装完不自动进入菜单" \
        "  --uninstall   卸载" \
        "环境变量: TB_BRANCH(分支) TB_BASE(下载基址)"
      exit 0 ;;
    *) shift ;;
  esac
done

if [ -z "$PREFIX" ]; then
  if [ "$(id -u)" = 0 ]; then PREFIX=/usr/local/bin; else PREFIX=$HOME/.local/bin; fi
fi

say() { printf '  %s\n' "$*"; }
die() { printf '  [x] %s\n' "$*" >&2; exit 1; }

fetch() { # $1=url $2=输出文件
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    return 127
  fi
}

# ------------------------------------------------------------------ 卸载 ----
if [ "$UNINSTALL" = 1 ]; then
  _removed=0
  for f in "$PREFIX/tb" "$PREFIX/traffic-burner"; do
    if [ -e "$f" ]; then rm -f "$f" && say "已删除 $f" && _removed=1; fi
  done
  [ "$_removed" = 1 ] || say "在 $PREFIX 下没找到已安装的文件"
  if [ -f /tmp/traffic-burner.pid ]; then
    _p=$(cat /tmp/traffic-burner.pid 2>/dev/null)
    if [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null; then
      say "注意: 仍有实例在运行 (pid $_p), 停止: kill $_p"
    fi
  fi
  exit 0
fi

# ------------------------------------------------------------------ 安装 ----
printf '\n  traffic-burner 一键安装\n'
printf '  ----------------------------------------\n'
_os=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null)
say "平台    : ${_os:-unknown}"
say "安装目录: $PREFIX"

mkdir -p "$PREFIX" || die "无法创建目录 $PREFIX"
TMPD=$(mktemp -d 2>/dev/null) || TMPD=/tmp/tb-install.$$
mkdir -p "$TMPD" || die "无法创建临时目录 $TMPD"

say "下载核心脚本..."
fetch "$BASE/traffic-burner.sh" "$TMPD/traffic-burner" \
  || die "下载失败: $BASE/traffic-burner.sh (检查网络, 或设置 TB_BASE 指向镜像)"
say "下载交互菜单..."
fetch "$BASE/tb.sh" "$TMPD/tb" \
  || die "下载失败: $BASE/tb.sh"

for f in traffic-burner tb; do
  [ -s "$TMPD/$f" ] || die "下载内容为空: $f"
  head -1 "$TMPD/$f" | grep -q '^#!/bin/sh' || die "内容不像预期脚本: $f"
done

say "安装到 $PREFIX ..."
cp "$TMPD/traffic-burner" "$PREFIX/traffic-burner" || die "复制失败"
cp "$TMPD/tb" "$PREFIX/tb" || die "复制失败"
chmod 755 "$PREFIX/traffic-burner" "$PREFIX/tb"
rm -rf "$TMPD"

if sh "$PREFIX/traffic-burner" -c >/dev/null 2>&1; then
  say "验证通过: 核心脚本可运行"
else
  say "[!] 验证未通过: 请手动运行 $PREFIX/traffic-burner -c 排查"
fi

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) say "[!] 注意: $PREFIX 不在 PATH 中, 建议: export PATH=\"$PREFIX:\$PATH\"" ;;
esac

if [ -f /tmp/traffic-burner.pid ]; then
  _p=$(cat /tmp/traffic-burner.pid 2>/dev/null)
  if [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null; then
    say "提示: 检测到实例正在运行 (pid $_p), 新脚本下次启动生效"
  fi
fi

printf '  ----------------------------------------\n'
say "安装完成! 命令:"
say "  tb                 打开交互菜单"
say "  traffic-burner -h  命令行用法"

# 交互环境: 直接进入菜单 (支持 curl | sh 的一键体验)
# 注意: 不能用 [ -r /dev/tty ] 判断 — 无控制终端时权限位仍在, 但打开会失败;
#       用子壳真正尝试打开, 失败也不会拖垮主流程。
if [ "$NORUN" = 0 ]; then
  if ( : < /dev/tty ) 2>/dev/null; then
    say "打开交互菜单..."
    exec "$PREFIX/tb" < /dev/tty
  fi
  printf '\n'
  say "运行 tb 打开交互菜单  (或 traffic-burner -h 查看命令行用法)"
fi
