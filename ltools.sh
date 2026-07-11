#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly LTOOLS_VERSION="1.0.0"
readonly CHECK_PLACE_URL="https://check.place"
readonly BBR_REPOSITORY="Eric86777/vps-tcp-tune"
readonly BBR_ENTRYPOINT="net-tcp-tune.sh"
readonly BBR_REF="${LTOOLS_BBR_REF:-main}"

OS_ID="unknown"
OS_NAME="Linux"
OS_LIKE=""
ACTIVE_TEMP_FILE=""

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly RESET=$'\033[0m'
    readonly CYAN=$'\033[36m'
    readonly GREEN=$'\033[32m'
    readonly WHITE=$'\033[1;37m'
    readonly YELLOW=$'\033[33m'
    readonly RED=$'\033[31m'
    readonly DIM=$'\033[2m'
else
    readonly RESET=""
    readonly CYAN=""
    readonly GREEN=""
    readonly WHITE=""
    readonly YELLOW=""
    readonly RED=""
    readonly DIM=""
fi

info() {
    printf '%b\n' "${CYAN}i${RESET}  $*"
}

success() {
    printf '%b\n' "${GREEN}OK${RESET} $*"
}

warn() {
    printf '%b\n' "${YELLOW}!${RESET}  $*"
}

error() {
    printf '%b\n' "${RED}x${RESET}  $*" >&2
}

die() {
    error "$*"
    exit 1
}

on_interrupt() {
    printf '\n%b\n' "${DIM}已退出 LTOOLS。${RESET}"
    exit 130
}

cleanup() {
    if [[ -n "${ACTIVE_TEMP_FILE}" ]]; then
        rm -f "${ACTIVE_TEMP_FILE}"
        ACTIVE_TEMP_FILE=""
    fi
}

trap cleanup EXIT
trap on_interrupt INT TERM

detect_system() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
        OS_LIKE="${ID_LIKE:-}"
    fi

    if [[ " ${OS_ID} ${OS_LIKE} " != *" debian "* ]]; then
        warn "当前系统为 ${OS_NAME}；本工具箱主要针对 Debian 系列测试。"
    fi
}

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        error "此操作需要 root 权限，但当前用户没有 sudo。"
        return 1
    fi
}

ensure_dependencies() {
    local command_name
    local -a missing=()

    for command_name in curl wget; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            missing+=("${command_name}")
        fi
    done

    if (( ${#missing[@]} == 0 )); then
        return 0
    fi

    info "缺少基础依赖：${missing[*]}。正在安装..."

    if ! command -v apt-get >/dev/null 2>&1; then
        die "未找到 apt-get，请先手动安装：${missing[*]}"
    fi

    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates "${missing[@]}"
    hash -r

    for command_name in curl wget; do
        command -v "${command_name}" >/dev/null 2>&1 || \
            die "依赖安装后仍未找到 ${command_name}。"
    done

    success "基础依赖已就绪。"
}

download_script() {
    local url="$1"
    local destination="$2"

    if curl -q --fail --silent --show-error --location \
        --proto '=https' --tlsv1.2 \
        --connect-timeout 15 --max-time 900 \
        --retry 2 --retry-delay 1 --retry-all-errors \
        --output "${destination}" "${url}"; then
        return 0
    fi

    warn "curl 下载失败，正在改用 wget 重试。"
    wget --quiet --https-only --timeout=30 --tries=3 \
        --output-document="${destination}" "${url}"
}

verify_script() {
    local script_file="$1"
    local checksum=""

    [[ -s "${script_file}" ]] || {
        error "下载结果为空。"
        return 1
    }

    if sed -n '1,8p' "${script_file}" | grep -Eqi '<(!doctype|html|head|body)([[:space:]>])'; then
        error "服务器返回了 HTML 页面，已拒绝执行。"
        return 1
    fi

    if ! bash -n "${script_file}"; then
        error "远程脚本未通过 Bash 语法检查，已拒绝执行。"
        return 1
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        checksum="$(sha256sum "${script_file}" | awk '{print $1}')"
        info "脚本 SHA-256：${checksum}"
    fi
}

run_remote_script() {
    local title="$1"
    local url="$2"
    local needs_root="$3"
    shift 3

    local script_file
    local exit_code=0
    script_file="$(mktemp "${TMPDIR:-/tmp}/ltools.XXXXXXXX.sh")" || {
        error "无法创建临时文件。"
        return 1
    }
    ACTIVE_TEMP_FILE="${script_file}"
    chmod 600 "${script_file}"

    printf '\n%b\n' "${WHITE}${title}${RESET}"
    info "来源：${url%%\?*}"

    if ! download_script "${url}" "${script_file}"; then
        error "下载失败，请检查 VPS 的 DNS 与网络连接。"
        rm -f "${script_file}"
        ACTIVE_TEMP_FILE=""
        return 1
    fi

    if ! verify_script "${script_file}"; then
        rm -f "${script_file}"
        ACTIVE_TEMP_FILE=""
        return 1
    fi

    chmod 700 "${script_file}"

    if [[ "${needs_root}" == "yes" ]]; then
        if run_as_root bash "${script_file}" "$@"; then
            exit_code=0
        else
            exit_code=$?
        fi
    elif bash "${script_file}" "$@"; then
        exit_code=0
    else
        exit_code=$?
    fi

    rm -f "${script_file}"
    ACTIVE_TEMP_FILE=""

    if (( exit_code == 0 )); then
        success "${title}已结束。"
    else
        error "${title}退出，状态码：${exit_code}"
    fi

    return "${exit_code}"
}

run_network_check() {
    run_remote_script "网络质量体检" "${CHECK_PLACE_URL}" "no" -N
}

run_hardware_check() {
    run_remote_script "硬件质量体检" "${CHECK_PLACE_URL}" "no" -H
}

run_bbr_tool() {
    local answer=""
    local url=""

    if [[ ! "${BBR_REF}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        error "LTOOLS_BBR_REF 含有非法字符。"
        return 1
    fi

    url="https://raw.githubusercontent.com/${BBR_REPOSITORY}/${BBR_REF}/${BBR_ENTRYPOINT}?_=$(date +%s)"

    printf '\n%b\n' "${WHITE}BBR 网络优化${RESET}"
    warn "此工具可能更换内核、修改网络参数并要求重启 VPS。"
    printf '%b' "${CYAN}继续运行上游脚本？${RESET} [y/N] "
    IFS= read -r answer || return 1

    case "${answer}" in
        y|Y|yes|YES|Yes)
            run_remote_script "BBR 网络优化" "${url}" "yes"
            ;;
        *)
            info "已取消 BBR 网络优化。"
            ;;
    esac
}

pause_menu() {
    printf '\n%b' "${DIM}按任意键返回主菜单...${RESET}"
    IFS= read -r -s -n 1 _ || true
    printf '\n'
}

clear_screen() {
    if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]] && command -v clear >/dev/null 2>&1; then
        clear
    fi
}

show_menu() {
    clear_screen
    printf '\n%b\n' "${WHITE}LTOOLS${RESET}  ${DIM}VPS diagnostics & tuning${RESET}"
    printf '%b\n' "${DIM}${OS_NAME} · v${LTOOLS_VERSION}${RESET}"
    printf '\n'
    printf '  %b1%b  网络质量体检      %bCheck.Place -N%b\n' "${CYAN}" "${RESET}" "${DIM}" "${RESET}"
    printf '  %b2%b  硬件质量体检      %bCheck.Place -H%b\n' "${CYAN}" "${RESET}" "${DIM}" "${RESET}"
    printf '  %b3%b  BBR 网络优化      %bvps-tcp-tune%b\n' "${GREEN}" "${RESET}" "${DIM}" "${RESET}"
    printf '\n'
    printf '  %b0%b  退出\n' "${DIM}" "${RESET}"
    printf '\n'
}

main() {
    local choice=""

    if [[ "${1:-}" == "--version" ]]; then
        printf 'LTOOLS %s\n' "${LTOOLS_VERSION}"
        return 0
    fi

    detect_system
    ensure_dependencies

    while true; do
        show_menu
        printf '%b' "${CYAN}请选择${RESET} [0-3]："
        if ! IFS= read -r choice; then
            printf '\n'
            return 0
        fi

        case "${choice}" in
            1)
                run_network_check || true
                pause_menu
                ;;
            2)
                run_hardware_check || true
                pause_menu
                ;;
            3)
                run_bbr_tool || true
                pause_menu
                ;;
            0|q|Q)
                printf '\n%b\n' "${DIM}已退出 LTOOLS。${RESET}"
                return 0
                ;;
            *)
                warn "无效选项，请输入 0、1、2 或 3。"
                pause_menu
                ;;
        esac
    done
}

main "$@"
