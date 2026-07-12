#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
category_menu "BBR / 网络优化" \
    "3|BBR 直连 / 落地优化（智能带宽检测）" \
    "5|DNS 净化与加固" \
    "6|Realm 转发 timeout 修复"
