# ssh-manager

一个交互式的 SSH 配置管理脚本，支持 **Debian / Ubuntu / Alpine Linux**。

无需记命令，一个菜单搞定 SSH 的密码登录、端口、密钥登录和公钥管理。

## 功能

- 查看 SSH 状态（服务运行、生效端口、密码/密钥/root 登录、各用户公钥数量）
- 开启 / 关闭 密码登录
- 修改 SSH 端口
- 开启 / 关闭 密钥登录（`PubkeyAuthentication`）
- 导入公钥（支持多行粘贴、自动去重、显示指纹）
- 查看 / 删除 公钥（支持 `1,3`、`2-4`、`all`）
- 修改公钥（整行替换，或只修改注释）
- 重启 SSH 服务、设置开机自启

## 支持系统

| 系统 | 服务管理 |
| --- | --- |
| Debian / Ubuntu | systemd（`ssh` / `sshd`） |
| Alpine Linux | OpenRC（`rc-service sshd`） |

脚本使用 POSIX `sh` 编写，可直接运行，无需安装额外依赖（依赖系统自带的 `sshd`、`ssh-keygen`）。

## 使用方法

```sh
# 下载
curl -fsSL https://raw.githubusercontent.com/LYISTR2/LTOOLS/main/ssh-manager/ssh-manager.sh -o ssh-manager.sh

# 运行（需要 root）
sudo sh ssh-manager.sh
```

仅查看状态 / 帮助（非交互）：

```sh
sudo sh ssh-manager.sh --status
sudo sh ssh-manager.sh --help
```

菜单：

```
 1) 查看 SSH 状态
 2) 开启 / 关闭 密码登录
 3) 修改 SSH 端口
 4) 开启 / 关闭 密钥登录
 5) 导入公钥
 6) 查看 / 删除 公钥
 7) 修改公钥
 8) 重启 SSH 服务
 9) 设置开机自启
 0) 退出
```

## 安全设计

- 修改配置前自动备份到 `/etc/ssh/ssh-manager-backups/时间戳/`
- 每次改完先用 `sshd -t` 做语法校验，再用 `sshd -T` 回读生效值
- **校验或重启失败时自动回滚**到修改前
- 关闭密码登录 / 关闭密钥登录前做“锁死”判断，避免把自己锁在服务器外
- 同步更新主配置与 `/etc/ssh/sshd_config.d/*.conf`，避免 Ubuntu 云镜像 drop-in 覆盖导致设置不生效
- 公钥文件自动修正权限（`.ssh` 为 `700`、`authorized_keys` 为 `600`）与属主，并提示 `StrictModes` / `AuthorizedKeysFile` 风险

## 注意事项

- 修改端口后：请先在防火墙 / 云服务器安全组放行新端口，再用新端口重连。现有连接通常不会断开，可保留当前会话以便测试。
- 需以 root 运行（`sudo`）。
- 首次运行若系统没有 SSH 主机密钥，脚本会自动执行 `ssh-keygen -A` 生成。
- 若 `AuthorizedKeysFile` 被自定义，导入公钥时会给出提示。

## 已验证环境

- Debian 13（trixie）：密码开关 + drop-in 同步、端口修改、公钥导入/删除/范围删除/改注释/整行替换、校验失败自动回滚、systemd 重启命令构造
- Alpine 3.24（Docker）：主机密钥自动补全、`--status`、密码开关、端口修改、公钥导入/删除、OpenRC 检测

## 可选环境变量

| 变量 | 说明 |
| --- | --- |
| `SSH_CONFIG` | 指定 sshd 配置文件路径 |
| `SSH_BACKUP_DIR` | 指定备份目录 |
| `SSH_MANAGER_NO_RESTART=1` | 只改配置、不重启服务（测试用） |

## License

[MIT](LICENSE)
