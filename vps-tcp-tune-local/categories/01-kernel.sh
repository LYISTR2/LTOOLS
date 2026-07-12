#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
category_menu "内核管理" \
    "1|安装 / 更新 XanMod 内核 + BBR v3" \
    "2|卸载 XanMod 内核"
