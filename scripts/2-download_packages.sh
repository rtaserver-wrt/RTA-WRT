#!/bin/bash

. ./scripts/0-includes.sh.sh

cd "${WORK_DIR}" || exit 1

SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"
TAG="$(firmware "TAG" "${VERSION}" "${SOURCE}")"

# Main function
main() {
    log "INFO" "Starting package downloader with precise filtering"
    
    init
    
    # Package definitions
    local packages=(
        "luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
        "luci-app-alpha-config|https://api.github.com/repos/animegasan/luci-app-alpha-config/releases/latest"
        "luci-theme-material3|https://api.github.com/repos/AngelaCooljx/luci-theme-material3/releases/latest"
        "luci-app-neko|https://api.github.com/repos/nosignals/openwrt-neko/releases/latest"
        "luci-theme-rtawrt|https://api.github.com/repos/rizkikotet-dev/luci-theme-rtawrt/releases/latest"
        "luci-app-netmonitor|https://api.github.com/repos/rizkikotet-dev/luci-app-netmonitor/releases/latest"
    )
    
    # Process downloads
    if process_packages packages "$SCRIPT_DIR/../packages"; then
        log "INFO" "All downloads completed successfully"
        exit 0
    else
        log "ERROR" "Some downloads failed"
        exit 1
    fi
}

# Setup signal handlers
trap cleanup EXIT INT TERM

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <package_list_file>"
        exit 1
    fi
    main "$@"
fi