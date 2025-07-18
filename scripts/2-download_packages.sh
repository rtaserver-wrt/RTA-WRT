#!/bin/bash

. ../scripts/0-includes.sh

WORK_DIR="${WORK_DIR:-$PWD}"
cd "${WORK_DIR}" || exit 1

SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"
TAG="$(firmware_id "TAG" "${VERSION}" "${SOURCE}")"
BRANCH="$(echo "${TAG}" | awk -F. '{print $1"."$2}')"


ARCH="$(device_id "ARCH_2" "$TARGET")"

# Validate architecture and dependencies
validate_environment() {
    if [ -z "$ARCH" ]; then
        log "ERROR" "Could not determine architecture for target: $TARGET"
        return 1
    fi

    # Check for required tools
    local required_tools=(curl wget jq tar gzip)
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "ERROR" "Missing required tools: ${missing_tools[*]}"
        return 1
    fi

    return 0
}

# Main function
main() {
    log "INFO" "Starting package downloader with precise filtering"
    
    if ! validate_environment; then
        return 1
    fi
    
    
    # Setup package repository URLs
    declare -A repo_urls
    
    if [[ "${VERSION}" == "snapshot" ]]; then
        repo_urls=(
            ["openwrt"]="https://downloads.openwrt.org/snapshots/packages/${ARCH}"
            ["immortalwrt"]="https://downloads.immortalwrt.org/snapshots/packages/${ARCH}"
            ["gspotx2f"]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/snapshot"
            ["rta"]="https://github.com/rizkikotet-dev/RTA-WRT_Packages/raw/releases/packages/SNAPSHOT/${ARCH}"
        )
    else
        repo_urls=(
            ["openwrt"]="https://downloads.openwrt.org/releases/${TAG}/packages/${ARCH}"
            ["immortalwrt"]="https://downloads.immortalwrt.org/releases/${TAG}/packages/${ARCH}"
            ["gspotx2f"]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
            ["rta"]="https://github.com/rizkikotet-dev/RTA-WRT_Packages/raw/releases/packages/${TAG}/${ARCH}"
        )
    fi
    
    # Validate repository URLs
    for repo in "${!repo_urls[@]}"; do
        local url="${repo_urls[$repo]}"
        log "INFO" "Validating repository: $repo at $url"
        if ! curl --output /dev/null --silent --head --fail "$url"; then
            log "WARN" "Repository $repo seems unreachable: $url"
        fi
    done
    
    # Package definitions by category
    declare -A package_groups
    
    # GitHub releases
    package_groups["github"]=(
        "luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
        "luci-app-netmonitor|https://api.github.com/repos/rizkikotet-dev/luci-app-netmonitor/releases/latest"
    )
    
    # RTA custom packages
    package_groups["rta"]=(
        "atinout|${repo_urls[rta]}"
        "luci-app-lite-watchdog|${repo_urls[rta]}"
    )
    
    # OpenWrt core packages
    package_groups["openwrt"]=(
        "modemmanager-rpcd|${repo_urls[openwrt]}/packages"
        "luci-proto-modemmanager|${repo_urls[openwrt]}/luci"
        "libqmi|${repo_urls[openwrt]}/packages"
        "libmbim|${repo_urls[openwrt]}/packages"
        "modemmanager|${repo_urls[openwrt]}/packages"
        "sms-tool|${repo_urls[openwrt]}/packages"
        "tailscale|${repo_urls[openwrt]}/packages"
        "python3-speedtest-cli|${repo_urls[openwrt]}/packages"
    )
    
    # ImmortalWrt packages
    package_groups["immortalwrt"]=(
        "luci-app-diskman|${repo_urls[immortalwrt]}/luci"
        "luci-app-zerotier|${repo_urls[immortalwrt]}/luci"
        "luci-app-ramfree|${repo_urls[immortalwrt]}/luci"
        "luci-app-3ginfo-lite|${repo_urls[immortalwrt]}/luci"
        "modemband|${repo_urls[immortalwrt]}/packages"
        "luci-app-modemband|${repo_urls[immortalwrt]}/luci"
        "luci-app-sms-tool-js|${repo_urls[immortalwrt]}/luci"
        "dns2tcp|${repo_urls[immortalwrt]}/packages"
        "luci-app-argon-config|${repo_urls[immortalwrt]}/luci"
        "luci-theme-argon|${repo_urls[immortalwrt]}/luci"
        "luci-app-openclash|${repo_urls[immortalwrt]}/luci"
        "luci-app-passwall|${repo_urls[immortalwrt]}/luci"
    )

    # GSPOTX2F packages
    package_groups["gspotx2f"]=(
        "luci-app-internet-detector|${repo_urls[gspotx2f]}"
        "internet-detector|${repo_urls[gspotx2f]}"
        "internet-detector-mod-modem-restart|${repo_urls[gspotx2f]}"
        "luci-app-cpu-status-mini|${repo_urls[gspotx2f]}"
        "luci-app-disks-info|${repo_urls[gspotx2f]}"
        "luci-app-log-viewer|${repo_urls[gspotx2f]}"
        "luci-app-temp-status|${repo_urls[gspotx2f]}"
    )
    
    # Process downloads by group
    local all_packages=()
    local failed_groups=()
    
    for group in "${!package_groups[@]}"; do
        log "INFO" "Processing $group packages..."
        if ! process_packages "package_groups[$group]" "$SCRIPT_DIR/../packages"; then
            log "ERROR" "Failed to process $group packages"
            failed_groups+=("$group")
        fi
        all_packages+=("${package_groups[$group][@]}")
    done
    
    # Summary
    local total=${#all_packages[@]}
    local failed=${#failed_groups[@]}
    local success=$((total - failed))
    
    log "INFO" "Download Summary:"
    log "INFO" "Total packages: $total"
    log "INFO" "Successfully downloaded: $success"
    
    if [ ${#failed_groups[@]} -gt 0 ]; then
        log "ERROR" "Failed groups: ${failed_groups[*]}"
        return 1
    fi
    
    log "INFO" "All package groups processed successfully"
    return 0
}

# Setup signal handlers
trap cleanup EXIT INT TERM

# Validate inputs
validate_inputs() {
    case "$SOURCE" in
        "openwrt"|"immortalwrt") ;;
        *) log "ERROR" "Invalid source: $SOURCE. Must be 'openwrt' or 'immortalwrt'"; return 1 ;;
    esac
    
    case "$VERSION" in
        "stable"|"snapshot"|"old-stable") ;;
        *) log "ERROR" "Invalid version: $VERSION. Must be 'stable', 'snapshot' or 'old-stable'"; return 1 ;;
    esac
    
    if ! device_id "ARCH_2" "$TARGET" >/dev/null; then
        log "ERROR" "Invalid target: $TARGET. Target not found in devices configuration"
        return 1
    fi
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 3 ]]; then
        log "ERROR" "Usage: $0 <source> <target> <version>"
        exit 1
    fi
    
    if ! validate_inputs; then
        exit 1
    fi
    
    if ! main "$@"; then
        exit 1
    fi
fi