#!/bin/bash

# OpenWrt Package Installation Script
# This script downloads and installs OpenClash, PassWall, and Nikki packages

# Source the include file containing common functions and variables
if [[ ! -f "./scripts/INCLUDE.sh" ]]; then
    echo "ERROR: INCLUDE.sh not found in ./scripts/" >&2
    exit 1
fi

# Set strict error handling
set -o errexit  # Exit on error
set -o nounset  # Exit on unset variables
set -o pipefail # Exit if any command in a pipe fails

# Source common functions and variables
# shellcheck source=./scripts/INCLUDE.sh
. ./scripts/INCLUDE.sh

# Constants
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly GH_API="https://api.github.com/repos"
readonly IMMORTALWRT_URL="https://downloads.immortalwrt.org/releases/packages-${VEROP}/${ARCH_3}/luci"
readonly TIMEOUT_DURATION=30
readonly MAX_RETRIES=3

# Validate required variables from INCLUDE.sh
validate_environment() {
    local required_vars=("VEROP" "ARCH_1" "ARCH_3")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error_msg "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    log "INFO" "Environment validation completed"
    return 0
}

# Initialize package arrays
declare -a openclash_ipk passwall_ipk
openclash_ipk=("luci-app-openclash|${IMMORTALWRT_URL}")
passwall_ipk=("luci-app-passwall|${IMMORTALWRT_URL}")

# Enhanced function to get latest release URL from GitHub with retry logic
get_github_release() {
    local repo="$1"
    local pattern="$2"
    local retry_count=0
    local result=""
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        log "DEBUG" "Attempting to fetch GitHub release for ${repo} (attempt $((retry_count + 1)))"
        
        if result=$(curl -s --connect-timeout "$TIMEOUT_DURATION" --max-time "$((TIMEOUT_DURATION * 2))" \
            "${GH_API}/${repo}/releases/latest" | \
            grep -E '"browser_download_url"' | \
            grep -oE "https://[^\"]*${pattern}[^\"]*" | \
            head -n 1); then
            
            if [[ -n "$result" ]]; then
                echo "$result"
                return 0
            fi
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            log "WARNING" "Retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    error_msg "Failed to get GitHub release for ${repo} after ${MAX_RETRIES} attempts"
    return 1
}

# Enhanced function to get any release URL from GitHub
get_github_release_any() {
    local repo="$1"
    local pattern="$2"
    local retry_count=0
    local result=""
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        log "DEBUG" "Attempting to fetch any GitHub release for ${repo} (attempt $((retry_count + 1)))"
        
        if result=$(curl -s --connect-timeout "$TIMEOUT_DURATION" --max-time "$((TIMEOUT_DURATION * 2))" \
            "${GH_API}/${repo}/releases" | \
            grep -E '"browser_download_url"' | \
            grep -oE "https://[^\"]*${pattern}[^\"]*" | \
            head -n 1); then
            
            if [[ -n "$result" ]]; then
                echo "$result"
                return 0
            fi
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            log "WARNING" "Retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    error_msg "Failed to get any GitHub release for ${repo} after ${MAX_RETRIES} attempts"
    return 1
}

# Enhanced function to get specific release tags from GitHub
get_github_release_tags() {
    local repo="$1"
    local tags="$2"
    local pattern="$3"
    local retry_count=0
    local result=""
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        log "DEBUG" "Attempting to fetch GitHub release tags for ${repo}/${tags} (attempt $((retry_count + 1)))"
        
        if result=$(curl -s --connect-timeout "$TIMEOUT_DURATION" --max-time "$((TIMEOUT_DURATION * 2))" \
            "${GH_API}/${repo}/releases/tags/${tags}" | \
            grep -E '"browser_download_url"' | \
            grep -oE "https://[^\"]*${pattern}[^\"]*" | \
            head -n 1); then
            
            if [[ -n "$result" ]]; then
                echo "$result"
                return 0
            fi
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            log "WARNING" "Retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    error_msg "Failed to get GitHub release tags for ${repo}/${tags} after ${MAX_RETRIES} attempts"
    return 1
}

# Function to construct GitHub raw file URL
get_github_browser_download_url() {
    local repo="$1"
    local branch="$2"
    local filepath="$3"
    
    # Validate inputs
    if [[ -z "$repo" || -z "$branch" || -z "$filepath" ]]; then
        error_msg "Invalid parameters for GitHub raw URL construction"
        return 1
    fi
    
    echo "https://raw.githubusercontent.com/${repo}/${branch}/${filepath}"
}

# Enhanced function to get release URL from GitHub HTML page
get_github_release_html() {
    local repo="$1"
    local pattern="$2"
    local retry_count=0
    local result=""
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        log "DEBUG" "Attempting to fetch GitHub HTML release for ${repo} (attempt $((retry_count + 1)))"
        
        if result=$(curl -s --connect-timeout "$TIMEOUT_DURATION" --max-time "$((TIMEOUT_DURATION * 2))" \
            "https://github.com/${repo}/releases/latest" | \
            grep -oE "/${repo}/releases/download/[^\"]*${pattern}[^\"]*" | \
            head -n 1 | \
            sed "s|^|https://github.com|"); then
            
            if [[ -n "$result" && "$result" != "https://github.com" ]]; then
                echo "$result"
                return 0
            fi
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            log "WARNING" "Retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    error_msg "Failed to get GitHub HTML release for ${repo} after ${MAX_RETRIES} attempts"
    return 1
}

# Create necessary directories
create_directories() {
    local directories=(
        "files/etc/openclash/core"
        "packages"
    )
    
    for dir in "${directories[@]}"; do
        if ! mkdir -p "$dir"; then
            error_msg "Failed to create directory: $dir"
            return 1
        fi
        log "DEBUG" "Created directory: $dir"
    done
    
    return 0
}

# Determine core file URLs
determine_core_files() {
    log "INFO" "Determining core file URLs..."
    
    # OpenClash core (raw file from 'core' branch)
    occore_file="clash-linux-${ARCH_1}"
    if ! openclash_core_url=$(get_github_browser_download_url "vernesong/OpenClash" "core" "meta/${occore_file}.tar.gz"); then
        error_msg "Failed to determine OpenClash core URL"
        return 1
    fi
    log "DEBUG" "OpenClash core URL: ${openclash_core_url}"

    # PassWall core (.zip from release)
    passwall_core_zip_pattern="passwall_packages_ipk_${ARCH_3}.*\.zip"
    if ! passwall_core_url=$(get_github_release_html "xiaorouji/openwrt-passwall" "$passwall_core_zip_pattern"); then
        error_msg "Failed to determine PassWall core URL"
        return 1
    fi
    log "DEBUG" "PassWall core URL: ${passwall_core_url}"

    # Nikki core (.tar.gz from release)
    nikki_core_pattern="nikki_${ARCH_3}-openwrt-${VEROP}.*\.tar.gz"
    if ! nikki_core_url=$(get_github_release_html "nikkinikki-org/OpenWrt-nikki" "$nikki_core_pattern"); then
        error_msg "Failed to determine Nikki core URL"
        return 1
    fi
    log "DEBUG" "Nikki core URL: ${nikki_core_url}"
    
    log "INFO" "Core file URLs determined successfully"
    return 0
}

# Enhanced function to download and extract package with validation
handle_package() {
    local url="$1"
    local dest="$2"
    local extract_cmd="$3"
    local temp_dest="${dest}.tmp"
    
    # Validate inputs
    if [[ -z "$url" || -z "$dest" || -z "$extract_cmd" ]]; then
        error_msg "Invalid parameters for package handling"
        return 1
    fi
    
    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$dest")
    if ! mkdir -p "$dest_dir"; then
        error_msg "Failed to create destination directory: $dest_dir"
        return 1
    fi
    
    log "INFO" "Downloading package from ${url}"
    
    # Download to temporary location first
    if ! ariadl "${url}" "${temp_dest}"; then
        error_msg "Failed to download package from ${url}"
        [[ -f "$temp_dest" ]] && rm -f "$temp_dest"
        return 1
    fi
    
    # Verify download (basic size check)
    if [[ ! -s "$temp_dest" ]]; then
        error_msg "Downloaded file is empty: ${temp_dest}"
        rm -f "$temp_dest"
        return 1
    fi
    
    # Move to final location
    if ! mv "$temp_dest" "$dest"; then
        error_msg "Failed to move downloaded file to final location"
        rm -f "$temp_dest"
        return 1
    fi

    log "INFO" "Extracting package ${dest}"
    if ! eval "${extract_cmd}"; then
        error_msg "Failed to extract package ${dest}"
        return 1
    fi

    log "INFO" "Successfully processed package ${dest}"
    return 0
}

# Enhanced OpenClash setup with better error handling
setup_openclash() {
    log "INFO" "Setting up OpenClash..."
    
    # Download IPK packages
    if ! download_packages openclash_ipk; then
        error_msg "Failed to download OpenClash IPK packages"
        return 1
    fi
    
    # Download and extract core
    if ! handle_package "${openclash_core_url}" "files/etc/openclash/core/clash.tar.gz" \
        "tar -xzf files/etc/openclash/core/clash.tar.gz -C files/etc/openclash/core --strip-components=0"; then
        error_msg "Failed to setup OpenClash core"
        return 1
    fi
    
    # Verify core extraction
    if [[ ! -f "files/etc/openclash/core/clash-linux-${ARCH_1}" ]]; then
        log "WARNING" "OpenClash core binary not found after extraction"
    fi
    
    log "INFO" "OpenClash setup completed successfully"
    return 0
}

# Enhanced PassWall setup
setup_passwall() {
    log "INFO" "Setting up PassWall..."
    
    # Download IPK packages
    if ! download_packages passwall_ipk; then
        error_msg "Failed to download PassWall IPK packages"
        return 1
    fi
    
    # Download and extract core
    if ! handle_package "${passwall_core_url}" "packages/passwall.zip" \
        "cd packages && unzip -qq passwall.zip && rm -f passwall.zip && cd .."; then
        error_msg "Failed to setup PassWall core"
        return 1
    fi
    
    log "INFO" "PassWall setup completed successfully"
    return 0
}

# Enhanced Nikki setup
setup_nikki() {
    log "INFO" "Setting up Nikki..."
    
    # Download and extract core
    if ! handle_package "${nikki_core_url}" "packages/nikki.tar.gz" \
        "tar -xzf packages/nikki.tar.gz -C packages && rm -f packages/nikki.tar.gz"; then
        error_msg "Failed to setup Nikki core"
        return 1
    fi
    
    log "INFO" "Nikki setup completed successfully"
    return 0
}

# Enhanced function to remove icons from theme files with backup
remove_icons() {
    local icons=("$@")
    local paths=(
        "files/usr/share/ucode/luci/template/themes/material/header.ut"
        "files/usr/lib/lua/luci/view/themes/argon/header.htm"
    )
    
    if [[ ${#icons[@]} -eq 0 ]]; then
        log "DEBUG" "No icons specified for removal"
        return 0
    fi
    
    for icon in "${icons[@]}"; do
        for path in "${paths[@]}"; do
            if [[ -f "${path}" ]]; then
                # Create backup before modification
                if ! cp "${path}" "${path}.backup.$(date +%s)" 2>/dev/null; then
                    log "WARNING" "Failed to create backup for ${path}"
                fi
                
                log "DEBUG" "Removing icon ${icon} from ${path}"
                if sed -i "/${icon}/d" "${path}"; then
                    log "DEBUG" "Successfully removed icon ${icon} from ${path}"
                else
                    log "WARNING" "Failed to remove icon ${icon} from ${path}"
                fi
            else
                log "DEBUG" "Theme file not found: ${path}"
            fi
        done
    done
}

# Cleanup function
cleanup() {
    log "INFO" "Performing cleanup..."
    
    # Remove temporary files
    find . -name "*.tmp" -type f -delete 2>/dev/null || true
    
    # Clean up any partial downloads
    find packages -name "*.partial" -type f -delete 2>/dev/null || true
}

# Signal handlers
trap cleanup EXIT
trap 'error_msg "Script interrupted"; exit 130' INT TERM

# Main function with comprehensive error handling
main() {
    local rc=0
    
    log "INFO" "Starting ${SCRIPT_NAME}"
    
    # Validate environment
    if ! validate_environment; then
        error_msg "Environment validation failed"
        exit 1
    fi
    
    # Create necessary directories
    if ! create_directories; then
        error_msg "Failed to create required directories"
        exit 1
    fi
    
    # Determine core files first
    if ! determine_core_files; then
        error_msg "Failed to determine core file URLs"
        rc=1
    fi
    
    # Setup packages
    if [[ $rc -eq 0 ]]; then
        setup_openclash || rc=1
        setup_passwall || rc=1  
        setup_nikki || rc=1
    fi

    if [[ $rc -ne 0 ]]; then
        error_msg "One or more package installations failed"
        exit 1
    else
        log "SUCCESS" "Package installation completed successfully"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi