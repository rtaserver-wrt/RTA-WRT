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

# Constants
readonly GH_API="https://api.github.com/repos"
readonly IMMORTALWRT_URL="https://downloads.immortalwrt.org/releases/packages-${VEROP}/${ARCH_3}/luci"

# Initialize variables
declare -a openclash_ipk passwall_ipk
openclash_ipk=("luci-app-openclash|${IMMORTALWRT_URL}")
passwall_ipk=("luci-app-passwall|${IMMORTALWRT_URL}")

# Function to get latest release URL from GitHub
get_github_release() {
    local repo="$1"
    local pattern="$2"
    curl -s "${GH_API}/${repo}/releases/latest" | \
    grep "browser_download_url" | \
    grep -oE "https.*${pattern}" | \
    head -n 1
}

# Function to get release URL from GitHub (non-latest)
get_github_release_any() {
    local repo="$1"
    local pattern="$2"
    curl -s "${GH_API}/${repo}/releases" | \
    grep "browser_download_url" | \
    grep -oE "https.*${pattern}" | \
    head -n 1
}

# Function to get specific release tags from GitHub
get_github_release_tags() {
    local repo="$1"
    local tags="$2"
    local pattern="$3"
    curl -s "${GH_API}/${repo}/releases/tags/${tags}" | \
    grep "browser_download_url" | \
    grep -oE "https.*${pattern}" | \
    head -n 1
}

get_github_browser_download_url() {
    local repo="$1"
    local branch="$2"
    local filepath="$3"
    echo "https://raw.githubusercontent.com/$repo/$branch/$filepath"
}

get_github_release_html() {
    local repo="$1"
    local pattern="$2"
    curl -s "https://github.com/${repo}/releases/latest" | \
    grep -oE "/${repo}/releases/download/[^\"]*${pattern}[^\"]*" | \
    head -n 1 | \
    sed "s|^|https://github.com|"
}


# Determine core file names
determine_core_files() {
    # OpenClash core (raw file di branch `core`)
    occore_file="clash-linux-${ARCH_1}"
    openclash_core_url=$(get_github_browser_download_url "vernesong/OpenClash" "core" "meta/${occore_file}.tar.gz")

    # PassWall core (.zip dari release)
    passwall_core_zip_pattern="passwall_packages_ipk_${ARCH_3}.*\.zip"
    passwall_core_url=$(get_github_release_html "xiaorouji/openwrt-passwall" "$passwall_core_zip_pattern")

    # Nikki core (.tar.gz dari release)
    nikki_core_pattern="nikki_${ARCH_3}-openwrt-${VEROP}.*\.tar.gz"
    nikki_core_url=$(get_github_release_html "nikkinikki-org/OpenWrt-nikki" "$nikki_core_pattern")
}

# Function to download and extract package
handle_package() {
    local url="$1"
    local dest="$2"
    local extract_cmd="$3"
    
    log "INFO" "Downloading package from ${url}"
    if ! ariadl "${url}" "${dest}"; then
        error_msg "Failed to download package from ${url}"
        return 1
    fi

    log "INFO" "Extracting package ${dest}"
    if ! eval "${extract_cmd}"; then
        error_msg "Failed to extract package ${dest}"
        return 1
    fi

    return 0
}

# Package setup functions
setup_openclash() {
    log "INFO" "Setting up OpenClash..."
    
    # Download IPK packages
    download_packages openclash_ipk || return 1
    
    # Download and extract core
    handle_package "${openclash_core_url}" "files/etc/openclash/core/clash.tar.gz" \
        "tar -xvf files/etc/openclash/core/clash.tar.gz -C files/etc/openclash/core" || return 1
    
    return 0
}

setup_passwall() {
    log "INFO" "Setting up PassWall..."
    
    # Download IPK packages
    download_packages passwall_ipk || return 1
    
    # Download and extract core
    handle_package "${passwall_core_url}" "packages/passwall.zip" \
        "unzip -qq packages/passwall.zip -d packages && rm packages/passwall.zip" || return 1
    
    return 0
}

setup_nikki() {
    log "INFO" "Setting up Nikki..."
    
    # Download and extract core
    handle_package "${nikki_core_url}" "packages/nikki.tar.gz" \
        "tar -xzf packages/nikki.tar.gz -C packages && rm packages/nikki.tar.gz" || return 1
    
    return 0
}

# Function to remove icons from theme files
remove_icons() {
    local icons=("$@")
    local paths=(
        "files/usr/share/ucode/luci/template/themes/material/header.ut"
        "files/usr/lib/lua/luci/view/themes/argon/header.htm"
    )
    
    for icon in "${icons[@]}"; do
        for path in "${paths[@]}"; do
            if [[ -f "${path}" ]]; then
                log "DEBUG" "Removing icon ${icon} from ${path}"
                sed -i "/${icon}/d" "${path}" || \
                    log "WARNING" "Failed to remove icon ${icon} from ${path}"
            else
                log "WARNING" "Theme file not found: ${path}"
            fi
        done
    done
}

# Main function
main() {
    local rc=0
    
    # Determine core files first
    determine_core_files || rc=1
    
    setup_openclash || rc=1
    setup_passwall || rc=1
    setup_nikki || rc=1

    if [[ ${rc} -ne 0 ]]; then
        error_msg "One or more package installations failed"
        exit 1
    else
        log "SUCCESS" "Package installation completed successfully"
    fi
}

# Execute main function
main "$@"