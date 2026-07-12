#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
category_menu "IP 质量检测" \
    "18|IP 质量检测（IPv4 + IPv6）" \
    "19|IP 质量检测（仅 IPv4）"
