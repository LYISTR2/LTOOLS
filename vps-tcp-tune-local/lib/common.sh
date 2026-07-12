#!/usr/bin/env bash

set -Eeuo pipefail

LOCAL_SUITE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_CORE="${LTOOLS_LOCAL_CORE:-${LOCAL_SUITE_ROOT}/upstream/net-tcp-tune.sh}"

local_error() {
    printf '\033[31m错误：\033[0m%s\n' "$*" >&2
}

run_core_action() {
    local action="$1"

    if [[ ! -f "${LOCAL_CORE}" ]]; then
        local_error "找不到本地共享核心：${LOCAL_CORE}"
        return 1
    fi

    if (( EUID == 0 )); then
        bash "${LOCAL_CORE}" --action "${action}"
    elif command -v sudo >/dev/null 2>&1; then
        sudo bash "${LOCAL_CORE}" --action "${action}"
    else
        local_error "此功能需要 root 权限，但当前用户没有 sudo。"
        return 1
    fi
}

category_menu() {
    local title="$1"
    shift
    local -a entries=("$@")
    local entry=""
    local number=""
    local label=""
    local choice=""
    local matched=0

    while true; do
        [[ -t 1 && "${TERM:-dumb}" != "dumb" ]] && clear
        printf '\n\033[1;36m%s\033[0m\n\n' "${title}"
        for entry in "${entries[@]}"; do
            IFS='|' read -r number label <<< "${entry}"
            printf '  \033[34m%3s\033[0m  %s\n' "${number}" "${label}"
        done
        printf '\n  \033[31m  0  返回分类菜单\033[0m\n\n'
        printf '请选择功能编号: '
        IFS= read -r choice || return 0

        [[ "${choice}" == "0" ]] && return 0
        matched=0
        for entry in "${entries[@]}"; do
            IFS='|' read -r number label <<< "${entry}"
            if [[ "${choice}" == "${number}" ]]; then
                matched=1
                if ! run_core_action "${number}"; then
                    local_error "功能 ${number} 执行失败。"
                fi
                break
            fi
        done

        if (( matched == 0 )); then
            local_error "无效功能编号：${choice}"
            sleep 1
        fi
    done
}
