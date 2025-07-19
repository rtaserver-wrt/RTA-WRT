#!/bin/bash
# OpenWrt Image Builder Script
# Version: 4.0 (Enhanced & Robust)
set -euo pipefail

# Color output for better visibility
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Error handler
error_handler() {
    local line_no=$1
    log_error "Script failed at line $line_no"
    log_error "Working directory: $(pwd)"
    exit 1
}
trap 'error_handler $LINENO' ERR

# Configuration with improved defaults
readonly WORK_DIR="${OPENWRT_WORK_DIR:-${PWD}/openwrt-build}"
readonly BASE="${1:-openwrt}"
readonly BRANCH="${2:-24.10.2}"
readonly TARGET_SYSTEM="${3:-x86/64}"
readonly TARGET_NAME="${4:-x86-64}"
readonly PROFILE="${5:-generic}"
readonly ARCH="${6:-x86_64}"
readonly PACKAGES_INCLUDE="${7:-dnsmasq-full luci luci-ssl-openssl}"
readonly PACKAGES_EXCLUDE="${8:--dnsmasq}"
readonly CUSTOM_FILES_DIR="files"
readonly JOBS="$(nproc)"

# Validate parameters
validate_parameters() {
    case "$BASE" in
        openwrt|immortalwrt) ;;
        *) log_error "Unsupported base: $BASE. Use 'openwrt' or 'immortalwrt'"; exit 1 ;;
    esac
    
    if [[ ! "$BRANCH" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        log_warn "Branch format unusual: $BRANCH (expected format: X.Y.Z)"
    fi
    
    if [[ ! "$TARGET_SYSTEM" =~ ^[a-z0-9_-]+/[a-z0-9_-]+$ ]]; then
        log_warn "TARGET_SYSTEM format unusual: $TARGET_SYSTEM (expected: arch/subarch)"
    fi
}

# Setup working environment
setup_environment() {
    log_info "Setting up build environment..."
    log_info "Working directory: $WORK_DIR"
    log_info "Base: $BASE, Branch: $BRANCH, Target: $TARGET_SYSTEM"
    
    # Create working directory with proper permissions
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Clean previous builds if requested
    if [[ "${CLEAN_BUILD:-0}" == "1" ]]; then
        log_info "Cleaning previous build artifacts..."
        rm -rf ./*
    fi
}

# Download and extract Image Builder
download_imagebuilder() {
    local url
    local ib_file
    
    case "$BASE" in
        "openwrt")
            url="https://downloads.openwrt.org/releases/$BRANCH/targets/$TARGET_SYSTEM/openwrt-imagebuilder-$BRANCH-$TARGET_NAME.Linux-x86_64.tar.zst"
            ;;
        "immortalwrt")
            url="https://downloads.immortalwrt.org/releases/$BRANCH/targets/$TARGET_SYSTEM/immortalwrt-imagebuilder-$BRANCH-$TARGET_NAME.Linux-x86_64.tar.zst"
            ;;
    esac
    
    ib_file=$(basename "$url")
    
    if [[ -f "$ib_file" ]] && [[ "${FORCE_DOWNLOAD:-0}" != "1" ]]; then
        log_info "Image builder already exists: $ib_file"
    else
        log_info "Downloading Image Builder: $url"
        if ! wget -q --show-progress "$url"; then
            log_error "Failed to download Image Builder from: $url"
            log_error "Please check if the URL is correct and accessible"
            exit 1
        fi
    fi
    
    # Verify download
    if [[ ! -f "$ib_file" ]] || [[ ! -s "$ib_file" ]]; then
        log_error "Downloaded file is missing or empty: $ib_file"
        exit 1
    fi
    
    log_info "Extracting Image Builder..."
    if ! tar -I zstd -xf "$ib_file" --strip-components=1; then
        log_error "Failed to extract Image Builder. Archive might be corrupted."
        exit 1
    fi
    
    log_success "Image Builder extracted successfully"
}

# Prepare custom files
prepare_custom_files() {
    local source_path="../$CUSTOM_FILES_DIR"
    
    if [[ -d "$source_path" ]]; then
        log_info "Copying custom files from $source_path"
        cp -r "$source_path" .
        
        # Set proper permissions for custom files
        find "$CUSTOM_FILES_DIR" -type f -exec chmod 644 {} \;
        find "$CUSTOM_FILES_DIR" -type d -exec chmod 755 {} \;
        
        # Make scripts executable
        find "$CUSTOM_FILES_DIR" -name "*.sh" -exec chmod +x {} \;
        
        log_success "Custom files prepared"
    else
        log_info "No custom files directory found at $source_path"
    fi
}

# Apply firmware-specific patches
apply_patches() {
    log_info "Applying firmware patches..."
    
    case "$BASE" in
        "immortalwrt")
            if [[ -f "include/target.mk" ]]; then
                sed -i "/luci-app-cpufreq/d" include/target.mk
                log_info "Applied ImmortalWrt cpufreq patch"
            fi
            ;;
    esac
    
    # Target-specific configurations
    case "$TARGET_NAME" in
        "armsr-armv8")
            log_info "Applying ARM64 specific configurations..."
            {
                echo "# ARM64 specific settings"
                echo "# CONFIG_TARGET_ROOTFS_CPIOGZ is not set"
                echo "# CONFIG_TARGET_ROOTFS_EXT4FS is not set" 
                echo "# CONFIG_TARGET_ROOTFS_SQUASHFS is not set"
                echo "# CONFIG_TARGET_IMAGES_GZIP is not set"
            } >> .config
            ;;
        "x86-64")
            log_info "Applying x86-64 specific configurations..."
            sed -i 's|CONFIG_ISO_IMAGES=y|# CONFIG_ISO_IMAGES is not set|' .config 2>/dev/null || true
            sed -i 's|CONFIG_VHDX_IMAGES=y|# CONFIG_VHDX_IMAGES is not set|' .config 2>/dev/null || true
            ;;
    esac
    
    # Disable signature checking for faster builds
    if [[ -f "repositories.conf" ]]; then
        sed -i '\|option check_signature| s|^|#|' repositories.conf
        log_info "Disabled package signature checking"
    fi
    
    log_success "Patches applied successfully"
}

# Build the firmware image
build_firmware() {
    log_info "Starting firmware build..."
    log_info "Profile: $PROFILE"
    log_info "Including packages: $PACKAGES_INCLUDE"
    log_info "Excluding packages: $PACKAGES_EXCLUDE"
    
    local make_cmd="make image"
    make_cmd+=" PROFILE=\"$PROFILE\""
    make_cmd+=" PACKAGES=\"$PACKAGES_INCLUDE $PACKAGES_EXCLUDE\""
    
    if [[ -d "$CUSTOM_FILES_DIR" ]]; then
        make_cmd+=" FILES=\"$CUSTOM_FILES_DIR\""
        log_info "Including custom files from: $CUSTOM_FILES_DIR"
    fi
    
    make_cmd+=" -j$JOBS"
    
    log_info "Build command: $make_cmd"
    log_info "Using $JOBS parallel jobs"
    
    # Record build start time
    local start_time=$(date +%s)
    
    if eval "$make_cmd"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "Build completed in ${duration}s"
    else
        log_error "Build failed!"
        log_error "Check the output above for error details"
        exit 1
    fi
}

# Display build results
show_results() {
    log_info "Build Results:"
    echo "=============================================="
    
    local image_files
    mapfile -t image_files < <(find bin/targets -type f \( -name "*.img.gz" -o -name "*.bin" -o -name "*.vmdk" -o -name "*.img" \) 2>/dev/null || true)
    
    if [[ ${#image_files[@]} -eq 0 ]]; then
        log_warn "No firmware images found in bin/targets"
        log_info "Checking for any files in bin/targets:"
        find bin/targets -type f 2>/dev/null || log_warn "bin/targets directory not found"
    else
        printf "%-50s %10s %20s\n" "File" "Size" "Modified"
        printf "%80s\n" | tr ' ' '-'
        
        for file in "${image_files[@]}"; do
            local size=$(du -h "$file" | cut -f1)
            local modified=$(date -r "$file" '+%Y-%m-%d %H:%M:%S')
            printf "%-50s %10s %20s\n" "$(basename "$file")" "$size" "$modified"
        done
        
        log_success "Found ${#image_files[@]} firmware image(s)"
        echo "Images location: $(pwd)/bin/targets"
    fi
    
    # Show additional artifacts
    local other_files
    mapfile -t other_files < <(find bin/targets -type f \( -name "*.buildinfo" -o -name "*.manifest" \) 2>/dev/null || true)
    
    if [[ ${#other_files[@]} -gt 0 ]]; then
        echo ""
        log_info "Additional build artifacts:"
        for file in "${other_files[@]}"; do
            echo "  - $(basename "$file")"
        done
    fi
}

# Main execution
main() {

    log_info "OpenWrt Image Builder Script v4.0"
    log_info "========================================="
    
    validate_parameters
    setup_environment
    download_imagebuilder
    prepare_custom_files
    apply_patches
    build_firmware
    show_results
    
    log_success "Script completed successfully!"
}

main "$@"