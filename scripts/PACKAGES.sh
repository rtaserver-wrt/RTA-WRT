#!/bin/bash

# Source the include file containing common functions and variables
if [[ ! -f "./scripts/INCLUDE.sh" ]]; then
    echo "ERROR: INCLUDE.sh not found in ./scripts/" >&2
    exit 1
fi

set -o errexit  # Exit on error
set -o nounset  # Exit on unset variables
set -o pipefail # Exit if any command in a pipe fails

. ./scripts/INCLUDE.sh

# Define repositories with proper quoting and error handling
declare -A REPOS
initialize_repositories() {
    local version="24.10"
    REPOS=(
        ["KIDDIN9"]="https://dl.openwrt.ai/releases/${version}/packages/${ARCH_3}/kiddin9"
        ["IMMORTALWRT"]="https://downloads.immortalwrt.org/releases/packages-${version}/${ARCH_3}"
        ["OPENWRT"]="https://downloads.openwrt.org/releases/packages-${version}/${ARCH_3}"
        ["GSPOTX2F"]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
        ["FANTASTIC"]="https://fantastic-packages.github.io/packages/releases/${VEROP}/packages/mipsel_24kc"
    )
}

# Define package categories with improved structure
declare_packages() {
    packages_custom=(
        # OPENWRT packages
        "modemmanager-rpcd_|${REPOS[OPENWRT]}/packages"
        "luci-proto-modemmanager_|${REPOS[OPENWRT]}/luci"
        "libqmi_|${REPOS[OPENWRT]}/packages"
        "libmbim_|${REPOS[OPENWRT]}/packages"
        "modemmanager_|${REPOS[OPENWRT]}/packages"
        "sms-tool_|${REPOS[OPENWRT]}/packages"
        "tailscale_|${REPOS[OPENWRT]}/packages"
        "python3-speedtest-cli_|${REPOS[OPENWRT]}/packages"

        # KIDDIN9 packages
        "luci-app-tailscale_|${REPOS[KIDDIN9]}"
        "luci-app-diskman_|${REPOS[KIDDIN9]}"
        "modeminfo-serial-zte_|${REPOS[KIDDIN9]}"
        "modeminfo-qmi_|${REPOS[KIDDIN9]}"
        "modeminfo-serial-dell_|${REPOS[KIDDIN9]}"
        "modeminfo-serial-sierra_|${REPOS[KIDDIN9]}"
        "modeminfo-serial-huawei_|${REPOS[KIDDIN9]}"
        "modeminfo-serial-xmm_|${REPOS[KIDDIN9]}"
        "modeminfo-serial-fibocom_|${REPOS[KIDDIN9]}"
        "modeminfo_|${REPOS[KIDDIN9]}"
        "luci-app-modeminfo_|${REPOS[KIDDIN9]}"
        "atinout_|${REPOS[KIDDIN9]}"
        "luci-app-poweroffdevice_|${REPOS[KIDDIN9]}"
        "xmm-modem_|${REPOS[KIDDIN9]}"
        "luci-app-lite-watchdog_|${REPOS[KIDDIN9]}"
        "luci-theme-alpha_|${REPOS[KIDDIN9]}"
        "luci-app-adguardhome_|${REPOS[KIDDIN9]}"
        "sing-box_|${REPOS[KIDDIN9]}"
        "luci-app-droidmodem_|${REPOS[KIDDIN9]}"

        # IMMORTALWRT packages
        "luci-app-zerotier_|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-ramfree_|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-3ginfo-lite_|${REPOS[IMMORTALWRT]}/luci"
        "modemband_|${REPOS[IMMORTALWRT]}/packages"
        "luci-app-modemband_|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-sms-tool-js_|${REPOS[IMMORTALWRT]}/luci"
        "dns2tcp_|${REPOS[IMMORTALWRT]}/packages"
        "luci-app-argon-config_|${REPOS[IMMORTALWRT]}/luci"
        "luci-theme-argon_|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-openclash_|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-passwall_|${REPOS[IMMORTALWRT]}/luci"

        # GSPOTX2F packages
        "luci-app-internet-detector_|${REPOS[GSPOTX2F]}"
        "internet-detector_|${REPOS[GSPOTX2F]}"
        "internet-detector-mod-modem-restart_|${REPOS[GSPOTX2F]}"
        "luci-app-cpu-status-mini_|${REPOS[GSPOTX2F]}"
        "luci-app-disks-info_|${REPOS[GSPOTX2F]}"
        "luci-app-log-viewer_|${REPOS[GSPOTX2F]}"
        "luci-app-temp-status_|${REPOS[GSPOTX2F]}"

        # FANTASTIC packages
        "luci-app-netspeedtest_|${REPOS[FANTASTIC]}/luci"

        # GitHub packages
        "luci-app-alpha-config_|https://api.github.com/repos/animegasan/luci-app-alpha-config/releases/latest"
        "luci-app-netmonitor_|https://api.github.com/repos/rizkikotet-dev/luci-app-netmonitor/releases/latest"
    )

    if [[ "${TYPE}" == "OPHUB" ]]; then
        log "INFO" "Adding Amlogic-specific packages..."
        packages_custom+=(
            "luci-app-amlogic_|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
        )
    fi
}

# Main execution function
main() {
    local rc=0

    initialize_repositories
    declare_packages

    # Download Custom packages
    log "INFO" "Downloading Custom packages..."
    if ! download_packages packages_custom; then
        rc=1
    fi

    if [[ $rc -eq 0 ]]; then
        log "SUCCESS" "All packages downloaded and verified successfully"
    else
        error_msg "Some packages failed to download or verify"
    fi

    return $rc
}

# Run main function if script is not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi