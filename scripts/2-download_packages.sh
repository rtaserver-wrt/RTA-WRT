#!/bin/bash

. ../scripts/0-includes.sh

WORK_DIR="${WORK_DIR:-$PWD}"
cd "${WORK_DIR}" || exit 1

SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"
TAG="$(firmware_id "TAG" "${VERSION}" "${SOURCE}")"
BRANCH="$(echo "${TAG}" | awk -F. '{print $1"."$2}')"

# Main function
main() {
    log "INFO" "Starting package downloader with precise filtering"
    
    
    local OpenWrt_URL ImmortalWrt_URL GSPOTX2F_URL
    if [[ "${VERSION}" == "snapshot" ]]; then
        OpenWrt_URL="https://downloads.openwrt.org/snapshots/packages/${TARGET}"
        ImmortalWrt_URL="https://downloads.immortalwrt.org/snapshots/packages/${TARGET}"
        GSPOTX2F_URL="https://github.com/gSpotx2f/packages-openwrt/tree/refs/heads/master/snapshot"
        RTA_PACKAGES_URL="https://github.com/rizkikotet-dev/RTA-WRT_Packages/tree/releases/packages/SNAPSHOT/${TARGET}"
    else
        OpenWrt_URL="https://downloads.openwrt.org/releases/packages-${BRANCH}/${TARGET}"
        ImmortalWrt_URL="https://downloads.immortalwrt.org/releases/packages-${BRANCH}/${TARGET}"
        GSPOTX2F_URL="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
        RTA_PACKAGES_URL="https://github.com/rizkikotet-dev/RTA-WRT_Packages/tree/releases/packages/${BRANCH}/${TARGET}"
    fi
    
    # Package definitions
    local packages=(
        "luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
        "luci-app-netmonitor|https://api.github.com/repos/rizkikotet-dev/luci-app-netmonitor/releases/latest"

        "atinout|$RTA_PACKAGES_URL"
        "luci-app-lite-watchdog|$RTA_PACKAGES_URL"

        # OpenWrt packages
        "modemmanager-rpcd|$OpenWrt_URL/packages"
        "luci-proto-modemmanager|$OpenWrt_URL/luci"
        "libqmi|$OpenWrt_URL/packages"
        "libmbim|$OpenWrt_URL/packages"
        "modemmanager|$OpenWrt_URL/packages"
        "sms-tool|$OpenWrt_URL/packages"
        "tailscale|$OpenWrt_URL/packages"
        "python3-speedtest-cli|$OpenWrt_URL/packages"

        # ImmortalWrt packages
        "luci-app-diskman|$ImmortalWrt_URL/luci"
        "luci-app-zerotier|$ImmortalWrt_URL/luci"
        "luci-app-ramfree|$ImmortalWrt_URL/luci"
        "luci-app-3ginfo-lite|$ImmortalWrt_URL/luci"
        "modemband|$ImmortalWrt_URL/packages"
        "luci-app-modemband|$ImmortalWrt_URL/luci"
        "luci-app-sms-tool-js|$ImmortalWrt_URL/luci"
        "dns2tcp|$ImmortalWrt_URL/packages"
        "luci-app-argon-config|$ImmortalWrt_URL/luci"
        "luci-theme-argon|$ImmortalWrt_URL/luci"
        "luci-app-openclash|$ImmortalWrt_URL/luci"
        "luci-app-passwall|$ImmortalWrt_URL/luci"

        # GSPOTX2F packages
        "luci-app-internet-detector|$GSPOTX2F_URL"
        "internet-detector|$GSPOTX2F_URL"
        "internet-detector-mod-modem-restart|$GSPOTX2F_URL"
        "luci-app-cpu-status-mini|$GSPOTX2F_URL"
        "luci-app-disks-info|$GSPOTX2F_URL"
        "luci-app-log-viewer|$GSPOTX2F_URL"
        "luci-app-temp-status|$GSPOTX2F_URL"
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
    if [[ $# -lt 3 ]]; then
        echo "Usage: $0 <source> <target> <version>"
        exit 1
    fi
    main "$@"
fi