#!/bin/bash
# Script: 2-download_packages.sh
# Fungsi: Mengunduh paket-paket tambahan dari berbagai repository sesuai konfigurasi.

set -e

# Determine script directory and include paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCLUDES_PATH="${SCRIPT_DIR}/0-includes.sh"

if [ ! -f "$INCLUDES_PATH" ]; then
    echo "ERROR: Required includes file not found: $INCLUDES_PATH"
    exit 1
fi

# Source includes
. "$INCLUDES_PATH"

# Setup working directory
WORK_DIR="${WORK_DIR:-$PWD}"
if ! cd "$WORK_DIR" 2>/dev/null; then
    log "ERROR" "Cannot change to working directory: $WORK_DIR"
    exit 1
fi

# Initialize variables
SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"

# Get firmware information
TAG="$(firmware_id "TAG" "${VERSION}" "${SOURCE}")"
if [ -z "$TAG" ]; then
    log "ERROR" "Could not determine firmware TAG"
    exit 1
fi

BRANCH="$(echo "${TAG}" | awk -F. '{print $1"."$2}')"
if [ -z "$BRANCH" ]; then
    log "ERROR" "Could not determine BRANCH from TAG: $TAG"
    exit 1
fi

ARCH="$(device_id "ARCH_2" "$TARGET")"
if [ -z "$ARCH" ]; then
    log "ERROR" "Could not determine architecture for target: $TARGET"
    exit 1
fi

# Global array to track downloaded packages
declare -a DOWNLOADED_PACKAGES=()

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

# Enhanced process_packages function with tracking
process_packages() {
    local -n pkg_array_ref=$1
    local download_dir="$2"
    local success_count=0
    local fail_count=0
    
    # Create download directory if it doesn't exist
    mkdir -p "$download_dir"
    
    for pkg_info in "${pkg_array_ref[@]}"; do
        local pkg_name=$(echo "$pkg_info" | cut -d'|' -f1)
        local pkg_url=$(echo "$pkg_info" | cut -d'|' -f2)
        
        log "INFO" "Processing package: $pkg_name"
        
        if download_package "$pkg_name" "$pkg_url" "$download_dir"; then
            DOWNLOADED_PACKAGES+=("$pkg_name")
            ((success_count++))
            log "INFO" "Successfully downloaded: $pkg_name"
        else
            ((fail_count++))
            log "ERROR" "Failed to download: $pkg_name"
        fi
    done
    
    log "INFO" "Package group processed: $success_count success, $fail_count failed"
    return $([ $fail_count -eq 0 ] && echo 0 || echo 1)
}

# Enhanced download function
download_package() {
    local pkg_name="$1"
    local pkg_url="$2"
    local download_dir="$3"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if [[ "$pkg_url" == *"api.github.com"* ]]; then
            # Handle GitHub releases
            if download_from_github "$pkg_name" "$pkg_url" "$download_dir"; then
                return 0
            fi
        else
            # Handle direct repository downloads
            if download_from_repo "$pkg_name" "$pkg_url" "$download_dir"; then
                return 0
            fi
        fi
        
        ((retry_count++))
        log "WARN" "Retry $retry_count/$max_retries for $pkg_name"
        sleep 2
    done
    
    return 1
}

# Download from GitHub releases
download_from_github() {
    local pkg_name="$1"
    local api_url="$2"
    local download_dir="$3"
    
    log "INFO" "Fetching GitHub release info for $pkg_name"
    
    # Get release information
    local release_info
    if ! release_info=$(curl -s "$api_url"); then
        log "ERROR" "Failed to fetch release info from $api_url"
        return 1
    fi
    
    # Extract download URLs for IPK files
    local download_urls
    download_urls=$(echo "$release_info" | jq -r '.assets[] | select(.name | test("\\.ipk$")) | .browser_download_url')
    
    if [ -z "$download_urls" ]; then
        log "ERROR" "No IPK files found in GitHub release for $pkg_name"
        return 1
    fi
    
    # Download each IPK file
    local downloaded=false
    while IFS= read -r url; do
        local filename=$(basename "$url")
        log "INFO" "Downloading $filename from GitHub"
        
        if curl -L -o "$download_dir/$filename" "$url"; then
            log "INFO" "Downloaded $filename"
            downloaded=true
        else
            log "ERROR" "Failed to download $filename"
        fi
    done <<< "$download_urls"
    
    return $([ "$downloaded" = true ] && echo 0 || echo 1)
}

# Download from repository
download_from_repo() {
    local pkg_name="$1"
    local repo_url="$2"
    local download_dir="$3"
    
    log "INFO" "Searching for $pkg_name in repository"
    
    # Try to find package in different subdirectories
    local subdirs=("" "base" "luci" "packages" "routing" "telephony")
    
    for subdir in "${subdirs[@]}"; do
        local search_url="$repo_url"
        [ -n "$subdir" ] && search_url="$repo_url/$subdir"
        
        log "INFO" "Checking $search_url for $pkg_name"
        
        # Get package list
        local pkg_list
        if pkg_list=$(curl -s "$search_url/Packages" 2>/dev/null); then
            # Search for package in the list
            local pkg_filename
            pkg_filename=$(echo "$pkg_list" | awk -v pkg="$pkg_name" '
                /^Package:/ { current_pkg = $2 }
                /^Filename:/ && current_pkg == pkg { print $2; exit }
            ')
            
            if [ -n "$pkg_filename" ]; then
                local download_url="$search_url/$pkg_filename"
                local local_filename=$(basename "$pkg_filename")
                
                log "INFO" "Found $pkg_name at $download_url"
                
                if curl -L -o "$download_dir/$local_filename" "$download_url"; then
                    log "INFO" "Downloaded $local_filename"
                    return 0
                else
                    log "ERROR" "Failed to download $local_filename"
                fi
            fi
        fi
    done
    
    return 1
}

# Verify downloaded packages
verify_packages() {
    log "INFO" "Verifying downloaded packages..."
    
    local packages_dir="$SCRIPT_DIR/../packages"
    local verified_packages=()
    local missing_packages=()
    local corrupted_packages=()
    
    # Check if packages directory exists
    if [ ! -d "$packages_dir" ]; then
        log "ERROR" "Packages directory not found: $packages_dir"
        return 1
    fi
    
    # Verify each downloaded package
    for pkg_name in "${DOWNLOADED_PACKAGES[@]}"; do
        log "INFO" "Verifying package: $pkg_name"
        
        # Find IPK files for this package
        local pkg_files
        pkg_files=$(find "$packages_dir" -name "*${pkg_name}*.ipk" 2>/dev/null)
        
        if [ -z "$pkg_files" ]; then
            log "WARN" "No IPK files found for package: $pkg_name"
            missing_packages+=("$pkg_name")
            continue
        fi
        
        # Verify each IPK file
        local pkg_verified=false
        while IFS= read -r pkg_file; do
            if [ -f "$pkg_file" ] && [ -s "$pkg_file" ]; then
                # Check if it's a valid IPK (actually a tar.gz file)
                if tar -tzf "$pkg_file" >/dev/null 2>&1; then
                    log "INFO" "Verified: $(basename "$pkg_file")"
                    pkg_verified=true
                else
                    log "ERROR" "Corrupted IPK: $(basename "$pkg_file")"
                    corrupted_packages+=("$(basename "$pkg_file")")
                fi
            else
                log "ERROR" "Invalid file: $(basename "$pkg_file")"
                corrupted_packages+=("$(basename "$pkg_file")")
            fi
        done <<< "$pkg_files"
        
        if [ "$pkg_verified" = true ]; then
            verified_packages+=("$pkg_name")
        fi
    done
    
    # Generate verification report
    log "INFO" "Package Verification Report:"
    log "INFO" "=========================="
    log "INFO" "Total packages processed: ${#DOWNLOADED_PACKAGES[@]}"
    log "INFO" "Successfully verified: ${#verified_packages[@]}"
    log "INFO" "Missing packages: ${#missing_packages[@]}"
    log "INFO" "Corrupted packages: ${#corrupted_packages[@]}"
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log "WARN" "Missing packages: ${missing_packages[*]}"
    fi
    
    if [ ${#corrupted_packages[@]} -gt 0 ]; then
        log "ERROR" "Corrupted packages: ${corrupted_packages[*]}"
    fi
    
    # Return list of verified packages as requested
    if [ ${#verified_packages[@]} -gt 0 ]; then
        echo "${verified_packages[*]}"
        return 0
    else
        return 1
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Script terminated with errors (exit code: $exit_code)"
    fi
    return $exit_code
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
            ["rta"]="https://github.com/rizkikotet-dev/RTA-WRT_Packages/raw/refs/heads/releases/packages/SNAPSHOT/${ARCH}"
        )
    else
        repo_urls=(
            ["openwrt"]="https://downloads.openwrt.org/releases/${TAG}/packages/${ARCH}"
            ["immortalwrt"]="https://downloads.immortalwrt.org/releases/${TAG}/packages/${ARCH}"
            ["gspotx2f"]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
            ["rta"]="https://dl.openwrt.ai/releases/${TAG}/packages/${ARCH}/kiddin9"
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
    local failed_groups=()
    
    for group in "${!package_groups[@]}"; do
        log "INFO" "Processing $group packages..."
        if ! process_packages "package_groups[$group]" "$SCRIPT_DIR/../packages"; then
            log "ERROR" "Failed to process $group packages"
            failed_groups+=("$group")
        fi
    done
    
    # Verify all downloaded packages
    local verified_list
    if verified_list=$(verify_packages); then
        log "INFO" "Package verification completed successfully"
        log "INFO" "Verified packages: $verified_list"
    else
        log "ERROR" "Package verification failed"
    fi
    
    # Summary
    local total=${#DOWNLOADED_PACKAGES[@]}
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