#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly LTOOLS_VERSION="2.2.0"
readonly CHECK_PLACE_URL="https://check.place"
readonly NODEQUALITY_URL="https://run.NodeQuality.com"
readonly NWS_URL="https://nws.sh"
readonly TCPQUALITY_URL="https://tcpquality.ibsgss.uk/run"
readonly SPEEDTEST_SETUP_URL="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
readonly SB_SOURCE_URL="https://raw.githubusercontent.com/0xdabiaoge/singbox-lite/main/singbox.sh"
readonly SB_INSTALL_PATH="${LTOOLS_SB_INSTALL_PATH:-/usr/local/bin/sb}"
readonly DOG_SOURCE_URL="https://raw.githubusercontent.com/zywe03/realm-xwPF/main/port-traffic-dog.sh"
readonly DOG_INSTALL_PATH="${LTOOLS_DOG_INSTALL_PATH:-/usr/local/bin/port-traffic-dog.sh}"
readonly NFT_SOURCE_URL="https://raw.githubusercontent.com/LYISTR2/nft-forward/main/nft-forward.sh"
readonly NFT_INSTALL_PATH="${LTOOLS_NFT_INSTALL_PATH:-/usr/local/bin/nft-forward}"
readonly BBR_REPOSITORY="Eric86777/vps-tcp-tune"
readonly BBR_ENTRYPOINT="net-tcp-tune.sh"
readonly BBR_REF="${LTOOLS_BBR_REF:-main}"

OS_ID="unknown"
OS_NAME="Linux"
OS_LIKE=""
ACTIVE_TEMP_FILE=""
UTF8_READY=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly RESET=$'\033[0m'
    readonly CYAN=$'\033[36m'
    readonly BRIGHT_CYAN=$'\033[1;36m'
    readonly BLUE=$'\033[34m'
    readonly GREEN=$'\033[32m'
    readonly WHITE=$'\033[1;37m'
    readonly YELLOW=$'\033[33m'
    readonly BOLD_YELLOW=$'\033[1;33m'
    readonly RED=$'\033[31m'
    readonly DIM=$'\033[2m'
    readonly DIM_GRAY=$'\033[2;37m'
else
    readonly RESET=""
    readonly CYAN=""
    readonly BRIGHT_CYAN=""
    readonly BLUE=""
    readonly GREEN=""
    readonly WHITE=""
    readonly YELLOW=""
    readonly BOLD_YELLOW=""
    readonly RED=""
    readonly DIM=""
    readonly DIM_GRAY=""
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

ensure_utf8_locale() {
    local charmap=""

    if command -v locale >/dev/null 2>&1; then
        charmap="$(locale charmap 2>/dev/null || true)"
        if [[ "${charmap}" =~ ^([Uu][Tt][Ff]-?8)$ ]]; then
            UTF8_READY=1
            return 0
        fi

        if [[ "$(LC_ALL=C.UTF-8 locale charmap 2>/dev/null || true)" =~ ^([Uu][Tt][Ff]-?8)$ ]]; then
            export LC_ALL=C.UTF-8
            UTF8_READY=1
            return 0
        fi
    fi

    UTF8_READY=0
}

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

run_nodequality_check() {
    run_remote_script "VPS 综合质量体检" "${NODEQUALITY_URL}" "no"
}

install_speedtest_cli() {
    local setup_file=""

    if ! command -v apt-get >/dev/null 2>&1; then
        error "未找到 apt-get，无法安装官方 Ookla Speedtest CLI。"
        return 1
    fi

    setup_file="$(mktemp "${TMPDIR:-/tmp}/ltools-speedtest.XXXXXXXX.sh")" || {
        error "无法创建临时文件。"
        return 1
    }
    ACTIVE_TEMP_FILE="${setup_file}"
    chmod 600 "${setup_file}"

    info "首次运行，正在配置 Ookla 官方软件源。"
    info "来源：${SPEEDTEST_SETUP_URL}"

    if ! download_script "${SPEEDTEST_SETUP_URL}" "${setup_file}"; then
        error "Speedtest 软件源配置脚本下载失败。"
        cleanup
        return 1
    fi

    if ! verify_script "${setup_file}"; then
        cleanup
        return 1
    fi

    if ! run_as_root bash "${setup_file}"; then
        error "Ookla 软件源配置失败。"
        cleanup
        return 1
    fi
    cleanup

    if ! run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y speedtest; then
        error "Speedtest CLI 安装失败。"
        return 1
    fi
    hash -r

    command -v speedtest >/dev/null 2>&1 || {
        error "安装完成后仍未找到 speedtest 命令。"
        return 1
    }

    success "Ookla Speedtest CLI 已安装。"
}

run_speedtest_cli() {
    local exit_code=0

    printf '\n%b\n' "${WHITE}Speedtest测速${RESET}"

    if ! command -v speedtest >/dev/null 2>&1; then
        install_speedtest_cli || return 1
    else
        info "使用已安装的本地命令：$(command -v speedtest)"
    fi

    if speedtest; then
        success "Speedtest测速已结束。"
    else
        exit_code=$?
        error "Speedtest测速退出，状态码：${exit_code}"
    fi

    return "${exit_code}"
}

run_international_speedtest() {
    run_remote_script "国际测速" "${NWS_URL}" "no"
}

run_tcpquality_check() {
    run_remote_script "TCP质量测试" "${TCPQUALITY_URL}" "yes"
}

install_persistent_tool() {
    local title="$1"
    local source_url="$2"
    local install_path="$3"
    local install_directory=""
    local script_file=""

    if [[ "${install_path}" != /* ]]; then
        error "${title}的安装路径必须是绝对路径。"
        return 1
    fi

    command -v install >/dev/null 2>&1 || {
        error "系统缺少 install 命令，无法部署 ${title}。"
        return 1
    }

    script_file="$(mktemp "${TMPDIR:-/tmp}/ltools-tool.XXXXXXXX.sh")" || {
        error "无法创建临时文件。"
        return 1
    }
    ACTIVE_TEMP_FILE="${script_file}"
    chmod 600 "${script_file}"

    info "首次运行，正在下载并部署到 ${install_path}"
    info "来源：${source_url}"

    if ! download_script "${source_url}" "${script_file}"; then
        error "${title}下载失败。"
        cleanup
        return 1
    fi

    if ! verify_script "${script_file}"; then
        cleanup
        return 1
    fi

    install_directory="$(dirname "${install_path}")"
    if [[ ! -d "${install_directory}" ]] && \
        ! run_as_root install -d -m 0755 "${install_directory}"; then
        error "无法创建安装目录：${install_directory}"
        cleanup
        return 1
    fi

    if ! run_as_root install -m 0755 "${script_file}" "${install_path}"; then
        error "无法安装到 ${install_path}"
        cleanup
        return 1
    fi

    cleanup
    success "${title}已持久安装。"
}

run_persistent_tool() {
    local title="$1"
    local source_url="$2"
    local install_path="$3"
    local exit_code=0

    printf '\n%b\n' "${WHITE}${title}${RESET}"

    if [[ -e "${install_path}" && ! -f "${install_path}" ]]; then
        error "安装路径已存在且不是普通文件：${install_path}"
        return 1
    fi

    if [[ ! -f "${install_path}" ]]; then
        install_persistent_tool "${title}" "${source_url}" "${install_path}" || return 1
    else
        info "使用已安装的本地工具：${install_path}"
        if [[ ! -r "${install_path}" || ! -x "${install_path}" ]] && \
            ! run_as_root chmod 0755 "${install_path}"; then
            error "无法为本地工具恢复执行权限。"
            return 1
        fi
    fi

    if ! bash -n "${install_path}"; then
        error "本地 ${title}未通过 Bash 语法检查，已拒绝执行。"
        return 1
    fi

    if run_as_root "${install_path}"; then
        success "${title}已结束。"
    else
        exit_code=$?
        error "${title}退出，状态码：${exit_code}"
    fi

    return "${exit_code}"
}

run_vps_node_builder() {
    run_persistent_tool "VPS节点搭建" "${SB_SOURCE_URL}" "${SB_INSTALL_PATH}"
}

run_traffic_dog() {
    run_persistent_tool "流量狗脚本" "${DOG_SOURCE_URL}" "${DOG_INSTALL_PATH}"
}

run_nft_forward() {
    run_persistent_tool "NFT 转发脚本" "${NFT_SOURCE_URL}" "${NFT_INSTALL_PATH}"
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

MENU_PLAIN_LINES=()
MENU_COLORED_LINES=()
MENU_NUMBER_WIDTH=2
MENU_LABEL_WIDTH=0
readonly MENU_DIVIDER_TOKEN="__LTOOLS_DIVIDER__"

codepoint_cell_width() {
    local codepoint="$1"

    if (( codepoint == 0 || codepoint < 32 || (codepoint >= 0x7f && codepoint < 0xa0) )); then
        REPLY=0
        return
    fi

    # Common combining marks, variation selectors and zero-width controls.
    if ((
        (codepoint >= 0x0300 && codepoint <= 0x036f) ||
        (codepoint >= 0x0483 && codepoint <= 0x0489) ||
        (codepoint >= 0x0591 && codepoint <= 0x05bd) || codepoint == 0x05bf ||
        (codepoint >= 0x05c1 && codepoint <= 0x05c2) ||
        (codepoint >= 0x0610 && codepoint <= 0x061a) ||
        (codepoint >= 0x064b && codepoint <= 0x065f) || codepoint == 0x0670 ||
        (codepoint >= 0x06d6 && codepoint <= 0x06ed) ||
        (codepoint >= 0x0711 && codepoint <= 0x074a) ||
        (codepoint >= 0x07a6 && codepoint <= 0x07b0) ||
        (codepoint >= 0x0816 && codepoint <= 0x082d) ||
        (codepoint >= 0x08d3 && codepoint <= 0x0902) ||
        (codepoint >= 0x1ab0 && codepoint <= 0x1aff) ||
        (codepoint >= 0x1dc0 && codepoint <= 0x1dff) ||
        (codepoint >= 0x200b && codepoint <= 0x200f) ||
        (codepoint >= 0x202a && codepoint <= 0x202e) ||
        (codepoint >= 0x2060 && codepoint <= 0x206f) ||
        (codepoint >= 0x20d0 && codepoint <= 0x20ff) ||
        (codepoint >= 0xfe00 && codepoint <= 0xfe0f) || codepoint == 0xfeff ||
        (codepoint >= 0xfe20 && codepoint <= 0xfe2f) ||
        (codepoint >= 0xe0100 && codepoint <= 0xe01ef)
    )); then
        REPLY=0
        return
    fi

    # Wide East Asian characters and emoji occupy two terminal cells.
    if ((
        codepoint >= 0x1100 && (
            codepoint <= 0x115f || codepoint == 0x2329 || codepoint == 0x232a ||
            (codepoint >= 0x2e80 && codepoint <= 0xa4cf && codepoint != 0x303f) ||
            (codepoint >= 0xac00 && codepoint <= 0xd7a3) ||
            (codepoint >= 0xf900 && codepoint <= 0xfaff) ||
            (codepoint >= 0xfe10 && codepoint <= 0xfe19) ||
            (codepoint >= 0xfe30 && codepoint <= 0xfe6f) ||
            (codepoint >= 0xff00 && codepoint <= 0xff60) ||
            (codepoint >= 0xffe0 && codepoint <= 0xffe6) ||
            (codepoint >= 0x1f300 && codepoint <= 0x1faff) ||
            (codepoint >= 0x20000 && codepoint <= 0x3fffd)
        )
    )); then
        REPLY=2
    else
        REPLY=1
    fi
}

display_width() {
    local text="$1"
    local character=""
    local codepoint=0
    local index=0
    local total=0
    local length=${#text}

    for (( index = 0; index < length; index++ )); do
        character="${text:index:1}"
        printf -v codepoint '%d' "'${character}" 2>/dev/null || codepoint=0
        codepoint_cell_width "${codepoint}"
        total=$(( total + REPLY ))
    done

    REPLY="${total}"
}

pad_to_display_width() {
    local text="$1"
    local target_width="$2"
    local padding=0
    local spaces=""

    display_width "${text}"
    padding=$(( target_width - REPLY ))
    (( padding < 0 )) && padding=0
    printf -v spaces '%*s' "${padding}" ""
    REPLY="${text}${spaces}"
}

add_menu_line() {
    MENU_PLAIN_LINES+=("$1")
    MENU_COLORED_LINES+=("$2")
}

add_menu_option() {
    local number="$1"
    local label="$2"
    local hint="$3"
    local number_field=""
    local label_field=""
    local plain_line=""
    local colored_line=""

    printf -v number_field "%${MENU_NUMBER_WIDTH}s" "${number}"
    pad_to_display_width "${label}" "${MENU_LABEL_WIDTH}"
    label_field="${REPLY}"

    plain_line="  ${number_field}  ${label_field}  ${hint}"
    colored_line="  ${BLUE}${number_field}${RESET}  ${label_field}  ${DIM_GRAY}${hint}${RESET}"
    add_menu_line "${plain_line}" "${colored_line}"
}

add_exit_option() {
    local number_field=""

    printf -v number_field "%${MENU_NUMBER_WIDTH}s" "0"
    add_menu_line "  ${number_field}  退出" "  ${RED}${number_field}  退出${RESET}"
}

build_menu_lines() {
    local index=0
    local value=""
    local width=0
    local -a test_numbers=("1" "2" "3" "4" "5" "6")
    local -a test_labels=("网络质量体检" "硬件质量体检" "VPS 综合质量体检" "Speedtest测速" "国际测速" "TCP质量测试")
    local -a test_hints=("Check.Place -N" "Check.Place -H" "NodeQuality" "Ookla · 本地" "nws.sh" "TcpQuality")
    local -a tool_numbers=("7" "8" "9" "10")
    local -a tool_labels=("BBR 网络优化" "VPS节点搭建" "流量狗脚本" "NFT 转发脚本")
    local -a tool_hints=("vps-tcp-tune" "singbox-lite · 本地" "port-traffic-dog · 本地" "nft-forward · 本地")
    local -a all_numbers=("${test_numbers[@]}" "${tool_numbers[@]}" "0")
    local -a all_labels=("${test_labels[@]}" "${tool_labels[@]}" "退出")

    MENU_PLAIN_LINES=()
    MENU_COLORED_LINES=()
    MENU_NUMBER_WIDTH=1
    MENU_LABEL_WIDTH=0

    for value in "${all_numbers[@]}"; do
        display_width "${value}"
        (( REPLY > MENU_NUMBER_WIDTH )) && MENU_NUMBER_WIDTH="${REPLY}"
    done
    for value in "${all_labels[@]}"; do
        display_width "${value}"
        (( REPLY > MENU_LABEL_WIDTH )) && MENU_LABEL_WIDTH="${REPLY}"
    done

    add_menu_line \
        "LTOOLS  VPS diagnostics & tuning" \
        "${BRIGHT_CYAN}LTOOLS${RESET}  ${DIM_GRAY}VPS diagnostics & tuning${RESET}"
    add_menu_line \
        "${OS_NAME} · v${LTOOLS_VERSION}" \
        "${DIM_GRAY}${OS_NAME} · v${LTOOLS_VERSION}${RESET}"
    add_menu_line "${MENU_DIVIDER_TOKEN}" "${MENU_DIVIDER_TOKEN}"

    add_menu_line "" ""
    add_menu_line "测试类" "${BOLD_YELLOW}测试类${RESET}"
    for index in "${!test_numbers[@]}"; do
        add_menu_option "${test_numbers[index]}" "${test_labels[index]}" "${test_hints[index]}"
    done

    add_menu_line "" ""
    add_menu_line "实用类工具" "${BOLD_YELLOW}实用类工具${RESET}"
    for index in "${!tool_numbers[@]}"; do
        add_menu_option "${tool_numbers[index]}" "${tool_labels[index]}" "${tool_hints[index]}"
    done

    add_menu_line "" ""
    add_exit_option
}

get_terminal_columns() {
    local columns=""
    local size=""

    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        columns="$(tput cols 2>/dev/null || true)"
    fi
    if [[ ! "${columns}" =~ ^[0-9]+$ || ${columns} -le 0 ]]; then
        size="$(stty size 2>/dev/null || true)"
        columns="${size##* }"
    fi
    if [[ ! "${columns}" =~ ^[0-9]+$ || ${columns} -le 0 ]]; then
        columns="${COLUMNS:-80}"
    fi
    [[ "${columns}" =~ ^[0-9]+$ ]] || columns=80
    REPLY="${columns}"
}

repeat_horizontal() {
    local count="$1"

    printf -v REPLY '%*s' "${count}" ""
    REPLY="${REPLY// /─}"
}

render_plain_menu() {
    local index=0

    for index in "${!MENU_PLAIN_LINES[@]}"; do
        [[ "${MENU_PLAIN_LINES[index]}" == "${MENU_DIVIDER_TOKEN}" ]] && continue
        printf '%s\n' "${MENU_COLORED_LINES[index]}"
    done
}

render_menu() {
    local index=0
    local line_width=0
    local max_line_width=0
    local horizontal_padding=2
    local inner_width=0
    local box_width=0
    local terminal_width=0
    local right_padding=0
    local border=""

    for index in "${!MENU_PLAIN_LINES[@]}"; do
        [[ "${MENU_PLAIN_LINES[index]}" == "${MENU_DIVIDER_TOKEN}" ]] && continue
        display_width "${MENU_PLAIN_LINES[index]}"
        line_width="${REPLY}"
        (( line_width > max_line_width )) && max_line_width="${line_width}"
    done

    inner_width=$(( max_line_width + horizontal_padding * 2 ))
    box_width=$(( inner_width + 2 ))
    get_terminal_columns
    terminal_width="${REPLY}"

    if [[ ! -t 1 ]] || (( UTF8_READY == 0 || terminal_width < box_width )); then
        render_plain_menu
        return
    fi

    repeat_horizontal "${inner_width}"
    border="${REPLY}"
    printf '┌%s┐\n' "${border}"

    for index in "${!MENU_PLAIN_LINES[@]}"; do
        if [[ "${MENU_PLAIN_LINES[index]}" == "${MENU_DIVIDER_TOKEN}" ]]; then
            printf '├%s┤\n' "${border}"
            continue
        fi

        display_width "${MENU_PLAIN_LINES[index]}"
        line_width="${REPLY}"
        right_padding=$(( inner_width - horizontal_padding - line_width ))
        printf '│%*s%s%*s│\n' \
            "${horizontal_padding}" "" \
            "${MENU_COLORED_LINES[index]}" \
            "${right_padding}" ""
    done

    printf '└%s┘\n' "${border}"
}

show_menu() {
    clear_screen
    build_menu_lines
    render_menu
}

main() {
    local choice=""

    if [[ "${1:-}" == "--version" ]]; then
        printf 'LTOOLS %s\n' "${LTOOLS_VERSION}"
        return 0
    fi

    ensure_utf8_locale
    detect_system
    ensure_dependencies

    while true; do
        show_menu
        printf '请选择 [0-10]: '
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
                run_nodequality_check || true
                pause_menu
                ;;
            4)
                run_speedtest_cli || true
                pause_menu
                ;;
            5)
                run_international_speedtest || true
                pause_menu
                ;;
            6)
                run_tcpquality_check || true
                pause_menu
                ;;
            7)
                run_bbr_tool || true
                pause_menu
                ;;
            8)
                run_vps_node_builder || true
                pause_menu
                ;;
            9)
                run_traffic_dog || true
                pause_menu
                ;;
            10)
                run_nft_forward || true
                pause_menu
                ;;
            0|q|Q)
                printf '\n%b\n' "${DIM}已退出 LTOOLS。${RESET}"
                return 0
                ;;
            *)
                warn "无效选项，请输入 0 到 10。"
                pause_menu
                ;;
        esac
    done
}

main "$@"
