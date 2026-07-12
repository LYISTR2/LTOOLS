#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CATEGORY_DIR="${SCRIPT_DIR}/categories"

while true; do
    [[ -t 1 && "${TERM:-dumb}" != "dumb" ]] && clear
    printf '\n\033[1;36mVPS TCP Tune · 本地分类版\033[0m\n'
    printf '\033[2m共享核心完全位于当前仓库，不在线拉取上游主脚本。\033[0m\n\n'
    printf '  \033[33m 1\033[0m  内核管理\n'
    printf '  \033[33m 2\033[0m  BBR / 网络优化\n'
    printf '  \033[33m 3\033[0m  系统配置\n'
    printf '  \033[33m 4\033[0m  代理部署\n'
    printf '  \033[33m 5\033[0m  IP 质量检测\n'
    printf '  \033[33m 6\033[0m  网络测试\n'
    printf '  \033[33m 7\033[0m  流媒体 / AI 检测\n'
    printf '  \033[33m 8\033[0m  第三方工具\n'
    printf '  \033[33m 9\033[0m  AI 代理服务\n'
    printf '  \033[33m10\033[0m  流量与端口管理\n'
    printf '  \033[33m11\033[0m  一键优化与维护\n'
    printf '\n  \033[31m 0  退出\033[0m\n\n'
    printf '请选择分类 [0-11]: '
    IFS= read -r choice || exit 0

    case "${choice}" in
        1) bash "${CATEGORY_DIR}/01-kernel.sh" ;;
        2) bash "${CATEGORY_DIR}/02-network-optimization.sh" ;;
        3) bash "${CATEGORY_DIR}/03-system.sh" ;;
        4) bash "${CATEGORY_DIR}/04-proxy.sh" ;;
        5) bash "${CATEGORY_DIR}/05-ip-quality.sh" ;;
        6) bash "${CATEGORY_DIR}/06-network-tests.sh" ;;
        7) bash "${CATEGORY_DIR}/07-media-ai.sh" ;;
        8) bash "${CATEGORY_DIR}/08-third-party.sh" ;;
        9) bash "${CATEGORY_DIR}/09-ai-proxy.sh" ;;
        10) bash "${CATEGORY_DIR}/10-traffic.sh" ;;
        11) bash "${CATEGORY_DIR}/11-automation.sh" ;;
        0) exit 0 ;;
        *) printf '\033[31m无效分类。\033[0m\n'; sleep 1 ;;
    esac
done
