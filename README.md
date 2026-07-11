# LTOOLS

一套面向 Debian VPS 的极简交互式测试与网络优化工具箱。

## 功能

| 选项 | 功能 | 上游入口 |
| ---: | --- | --- |
| 1 | 网络质量体检 | `https://check.place`，参数 `-N` |
| 2 | 硬件质量体检 | `https://check.place`，参数 `-H` |
| 3 | BBR 网络优化 | `Eric86777/vps-tcp-tune` 的 `net-tcp-tune.sh` |
| 0 | 退出 | — |

脚本会自动检查 `curl` 和 `wget`。Debian 系统缺少依赖时，会通过 `apt-get` 安装 `ca-certificates`、`curl` 和 `wget`。每项任务结束后，按任意键即可回到主菜单。

## 直接运行

```bash
chmod +x ltools.sh
sudo ./ltools.sh
```

也可以使用 Bash 运行：

```bash
sudo bash ltools.sh
```

BBR 工具会修改内核或网络参数，运行前有独立确认步骤。首次安装新内核后，请按照上游脚本提示决定是否重启，不要在没有 VPS 控制台或快照的情况下盲目操作。

## 部署为 GitHub 私有仓库

仓库应先按照 [GitHub 官方可见性说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility) 设为私有：

1. 打开仓库的 **Settings → General**。
2. 在页面底部找到 **Danger Zone → Change repository visibility**。
3. 选择 **Make private**，按 GitHub 提示确认仓库名。
4. 合并包含 `ltools.sh` 和本说明的 PR 到 `main`。

不要把 GitHub Token、VPS 密码、SSH 私钥或其他凭据提交到仓库。

## 在 VPS 安全调用私有脚本

### 推荐：GitHub CLI

先在 VPS 安装 [GitHub CLI](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)，然后按 [GitHub CLI 认证说明](https://cli.github.com/manual/gh_auth_login) 登录：

```bash
gh auth login --hostname github.com --git-protocol https --web
gh auth status
```

选择 GitHub.com 和 HTTPS。无桌面的 VPS 会显示一次性代码；在自己的浏览器中完成授权即可。`gh` 会优先使用系统凭据存储；如果系统没有可用的凭据存储，它可能回退到普通文本文件。请用 `gh auth status` 检查存储位置和状态。

之后粘贴下面这一条命令即可运行私有仓库 `main` 分支中的脚本：

```bash
bash -c 'set -Eeuo pipefail; f="$(mktemp)"; trap '\''rm -f "$f"'\'' EXIT; gh api -H "Accept: application/vnd.github.raw+json" -H "X-GitHub-Api-Version: 2022-11-28" "/repos/LYISTR2/LTOOLS/contents/ltools.sh?ref=main" >"$f"; bash -n "$f"; chmod 700 "$f"; if (( EUID == 0 )); then bash "$f"; elif command -v sudo >/dev/null 2>&1; then sudo bash "$f"; else printf "需要 root 或 sudo。\n" >&2; exit 1; fi'
```

这条命令不会把 Token 写进命令行或 shell 历史；它使用 [GitHub Contents API 的 raw 响应](https://docs.github.com/en/rest/repos/contents?apiVersion=2022-11-28#get-repository-content)，先下载到权限受限的临时文件，再做 Bash 语法检查，最后执行并自动删除临时文件。

不建议使用 `curl <private-raw-url> | bash`：私有文件需要认证，把 Token 拼进 URL 会泄露到历史、日志或进程信息，而管道执行也没有下载检查和临时文件审阅环节。

如需日常使用，可在 VPS 上创建一个只属于 root 的快捷命令：

```bash
sudo install -d -m 700 /root/bin
sudo tee /root/bin/ltools >/dev/null <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
file="$(mktemp)"
trap 'rm -f "$file"' EXIT
gh api \
  -H "Accept: application/vnd.github.raw+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/LYISTR2/LTOOLS/contents/ltools.sh?ref=main" >"$file"
bash -n "$file"
chmod 700 "$file"
bash "$file"
EOF
sudo chmod 700 /root/bin/ltools
```

以后执行：

```bash
sudo /root/bin/ltools
```

如果 `gh` 是以普通用户身份登录的，请使用前面的单行命令；`sudo` 默认看不到普通用户的 `gh` 登录状态。若希望 `/root/bin/ltools` 直接可用，应执行 `sudo gh auth login`，让 root 拥有独立的最小权限认证。

### 无 GitHub CLI：Fine-grained PAT

GitHub CLI 是首选。如果必须使用 Token，请创建仅限 `LYISTR2/LTOOLS`、仅有 **Contents: Read-only** 权限的 Fine-grained PAT。运行时交互输入，不要把 Token 写进 URL、脚本或命令历史：

```bash
bash <<'BASH'
set -Eeuo pipefail
read -rsp 'GitHub Token: ' GITHUB_TOKEN; echo
workdir="$(mktemp -d)"
trap 'unset GITHUB_TOKEN; rm -rf "$workdir"' EXIT
chmod 700 "$workdir"
printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN" >"$workdir/curl.conf"
chmod 600 "$workdir/curl.conf"
curl -qfsSL --proto '=https' --tlsv1.2 \
  --config "$workdir/curl.conf" \
  -H 'Accept: application/vnd.github.raw+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  'https://api.github.com/repos/LYISTR2/LTOOLS/contents/ltools.sh?ref=main' \
  -o "$workdir/ltools.sh"
unset GITHUB_TOKEN
bash -n "$workdir/ltools.sh"
if (( EUID == 0 )); then
  bash "$workdir/ltools.sh"
elif command -v sudo >/dev/null 2>&1; then
  sudo bash "$workdir/ltools.sh"
else
  printf '需要 root 或 sudo。\n' >&2
  exit 1
fi
BASH
```

用完不再需要时，请在 GitHub 的 **Settings → Developer settings → Personal access tokens** 中撤销该 Token。

## 更新与固定版本

上面的调用默认读取 `main` 最新版本。对稳定性要求较高时，可以把 `ref=main` 改成已审核的提交 SHA，从而固定工具箱版本。

BBR 上游默认跟随 `main`。如需固定上游版本，可传入提交 SHA：

```bash
sudo LTOOLS_BBR_REF='<commit-sha>' bash ltools.sh
```

## 安全说明

LTOOLS 会在运行时下载第三方脚本。下载过程强制 HTTPS，拒绝空文件和常见 HTML 错误页，执行前运行 `bash -n` 并显示 SHA-256；这些措施能发现传输与格式异常，但不能证明第三方代码本身可信。重要 VPS 应先创建快照，并在执行前审阅上游变更或固定提交 SHA。

上游项目：

- [Check.Place](https://check.place)
- [Eric86777/vps-tcp-tune](https://github.com/Eric86777/vps-tcp-tune)
