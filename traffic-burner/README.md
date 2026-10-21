# traffic-burner 🔥

跨发行版（**Debian / Ubuntu / Alpine**）的「消耗自己服务器流量」小工具。
纯 POSIX sh 编写（dash 与 BusyBox ash 通吃），除 `curl` 外零依赖（缺失时自动用 `apt` / `apk` 安装）。

> ⚠️ 仅用于消耗**自己拥有或已获授权**的服务器流量。
> 默认下载源为公开测速节点（示例性质），请遵守目标站条款；长期使用建议换成自己可控的源。

## 一键安装

```sh
curl -fsSL https://raw.githubusercontent.com/LYISTR2/LTOOLS/main/traffic-burner/install.sh | sh
```

装完自动进入交互菜单；以后随时运行 `tb` 打开菜单，或 `traffic-burner` 直接用命令行。

## 交互菜单（tb）

```
 1) 快跑 100 MB       (下载, 2 并发)
 2) 标准 1 GB         (下载, 4 并发)
 3) 挂机 1 小时       (下载, 4 并发, 不限量)
 4) 自定义运行        (下载/上传, 时长/流量/并发/限速)
 5) 查看状态
 6) 停止
 7) 平台自检
 8) 帮助
 0) 退出
```

菜单里启动的任务都在后台跑，`5` 看进度/日志、`6` 优雅停止（会打汇总）。

## 命令行用法

| 用途 | 命令 |
|---|---|
| 1 小时, 4 并发 | `traffic-burner -d 3600 -w 4` |
| 刷 500 MB, 每并发限速 20MB/s | `traffic-burner -t 500 -r 20M` |
| 自定义下载源 | `traffic-burner -u "https://你的源/big.bin"` |
| 上行烧流量 | `traffic-burner -m upload -u "http://另一台机:18080/up"` |
| 平台自检 | `traffic-burner -c` |
| 常驻后台 | `nohup traffic-burner -d 86400 >/dev/null 2>&1 &` |
| 停止 | `kill $(cat /tmp/traffic-burner.pid)` 或菜单 `6` |

完整参数：`traffic-burner -h`（`-d` 时长 / `-t` 目标MB / `-w` 并发 / `-r` 限速 / `-u` URL / `-f` URL文件 / `-m` 模式 / `-i` 网卡 / `-l` 日志）。

## 常见问题

- **流量怎么统计的？** 读 `/proc/net/dev` 前后差值：下载看 RX（下行）、上传看 TX（上行），汇总里两个方向都给出，口径贴近厂商计费。
- **为什么实际跑出来比目标多一点？** 目标检查每 3 秒一次（`TICK=秒` 可调），且 curl `--limit-rate` 启动初期有突发，属正常。
- **Cloudflare 源为什么是 50MB 一档？** `speed.cloudflare.com/__down` 单请求超过约 50MB 会返回 403，脚本已避开。
- **Alpine 上没有 curl？** 脚本检测到缺失会自动 `apk add curl ca-certificates`；Debian/Ubuntu 走 `apt`。
- **上传模式的目标地址哪来？** 需要一台你能控制的接收机。附带一个极简接收器：`extras/recv-server.py`（python3 运行即可）：`python3 recv-server.py 18080`。

## 卸载

```sh
curl -fsSL https://raw.githubusercontent.com/LYISTR2/LTOOLS/main/traffic-burner/install.sh | sh -s -- --uninstall
```

## 文件

```
traffic-burner.sh      核心引擎 (纯 POSIX sh)
tb.sh                  交互式控制台 (安装后命令名 tb)
install.sh             一键安装/卸载
extras/recv-server.py  可选: upload 模式的极简接收端 (python3)
```

## 实测环境

`alpine:3.20` / `debian:12` / `ubuntu:24.04` 容器 + Debian 13 宿主机全部跑通（含自动安装依赖、目标/时长/信号停止、上传端到端、单实例锁）。

## License

MIT
