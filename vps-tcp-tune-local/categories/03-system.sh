#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
category_menu "系统配置" \
    "7|设置 IPv4 / IPv6 优先级" \
    "8|IPv6 管理" \
    "9|设置临时 SOCKS5 代理" \
    "10|虚拟内存管理" \
    "11|查看系统详细状态"
