# LTOOLS

面向 Debian VPS 的交互式工具箱，集成网络检测、节点管理、端口转发和 SSH 管理。

## 运行 / 更新

需要 `bash`、`curl`；系统管理功能需要 root 或 sudo 权限。在可写目录执行，重复运行即可获取最新版：

```bash
curl -fsSLO https://raw.githubusercontent.com/LYISTR2/LTOOLS/main/ltools.sh && bash ltools.sh
```

已下载后直接运行：

```bash
bash ltools.sh
```

## 功能

- **检测（1–6）**：网络质量、硬件性能、VPS 综合评测、Ookla 带宽测速、国际网络测速、TCP 连接质量。
- **网络管理（7–10）**：BBR 与网络优化、代理节点管理、端口流量与限额管理、nftables 端口转发。
- **应用（11–12）**：CLIProxyAPI 安装、Telegram 关键词机器人。
- **SSH（13–14）**：密码与公钥登录管理、端口修改、公钥维护、临时 SSH 账号。
- **流量（15）**：定量或定时上传 / 下载。

输入编号执行，`0` 或 `q` 退出。输错可直接重试；检测结束后回车返回，也可输入下一项编号。

## 工具来源与更新

- BBR 使用 [Eric86777/vps-tcp-tune](https://github.com/Eric86777/vps-tcp-tune)。
- 节点管理和端口流量管理每次从 [singbox-lite](https://github.com/0xdabiaoge/singbox-lite)、[realm-xwPF](https://github.com/zywe03/realm-xwPF) 下载，失败不运行旧版；为兼容上游定时任务，保留稳定安装路径。
- 自有工具：[NFT 转发](nft-forward/README.md)、[SSH 管理](ssh-manager/README.md)、[流量工具](traffic-burner/README.md)。SSH 菜单每次获取最新版；重新选择菜单 `15` 更新流量工具；NFT 首次安装后使用本地版本，可在工具内更新。

曾从旧独立仓库安装 NFT 工具的用户，执行一次迁移（root 用户去掉 `sudo`）：

```bash
curl -fsSLo nft-forward.sh https://raw.githubusercontent.com/LYISTR2/LTOOLS/main/nft-forward/nft-forward.sh && bash -n nft-forward.sh && sudo install -m 0755 nft-forward.sh /usr/local/bin/nft-forward
```

## 注意

- 主菜单面向 Debian；内置 SSH 与流量工具支持 Debian / Ubuntu / Alpine，第三方工具兼容性以各自说明为准。
- 测速和流量任务会消耗额度；100 MB / 1000 MB 预设选中即启动。
- SSH、防火墙和内核操作可能影响连接，操作前保留现有 SSH 会话，并准备快照或控制台。
- 下载检查不等于代码安全审计；仅在信任上游代码时运行，不要将密码、密钥或 Token 提交到仓库。
