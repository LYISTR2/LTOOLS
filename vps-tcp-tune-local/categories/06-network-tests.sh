#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
category_menu "网络测试" \
    "20|服务器带宽测试" \
    "21|iperf3 单线程测试" \
    "22|国际互联速度测试" \
    "23|网络延迟质量检测" \
    "24|三网回程路由测试"
