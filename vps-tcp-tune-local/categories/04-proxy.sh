#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
category_menu "代理部署" \
    "12|Snell 协议管理" \
    "13|Xray 一键多协议" \
    "14|禁止端口通过中国大陆直连" \
    "15|SOCKS5 代理管理" \
    "16|Sub-Store 多实例管理" \
    "17|一键反向代理"
