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
readonly PACKAGES_INCLUDE="${7:-dnsmasq-full cgi-io libiwinfo libiwinfo-data libiwinfo-lua liblua \
luci-base luci-lib-base luci-lib-ip luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
cpusage ttyd dmesg kmod-tun luci-lib-ipkg git git-http \
zram-swap adb parted losetup resize2fs luci luci-ssl block-mount htop bash curl wget-ssl \
tar unzip unrar gzip jq luci-app-ttyd nano httping screen openssh-sftp-server \
liblucihttp liblucihttp-lua libubus-lua lua luci-app-firewall luci-app-opkg \
ca-bundle ca-certificates luci-compat coreutils-sleep fontconfig coreutils-whoami file lolcat \
luci-base luci-lib-base luci-lib-ip luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
luci-mod-network luci-mod-status luci-mod-system luci-proto-ipv6 luci-proto-ppp \
luci-theme-bootstrap rpcd rpcd-mod-file rpcd-mod-iwinfo rpcd-mod-luci \
rpcd-mod-rrdns uhttpd uhttpd-mod-ubus coreutils coreutils-base64 coreutils-nohup coreutils-stty libc coreutils-stat coreutils-timeout \
ip-full libuci-lua microsocks resolveip ipset iptables iptables-legacy \
iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy kmod-ipt-nat luci-lua-runtime zoneinfo-asia zoneinfo-core \
perl perlbase-base perlbase-bytes perlbase-class perlbase-config perlbase-cwd perlbase-dynaloader perlbase-errno perlbase-essential perlbase-fcntl perlbase-file \
perlbase-filehandle perlbase-i18n perlbase-integer perlbase-io perlbase-list perlbase-locale perlbase-params perlbase-posix \
perlbase-re perlbase-scalar perlbase-selectsaver perlbase-socket perlbase-symbol perlbase-tie perlbase-time perlbase-unicore perlbase-utf8 perlbase-xsloader \
php8 php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo php8-mod-zip php8-mod-iconv php8-mod-mbstring \
luci-theme-material kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179 \
 kmod-mii kmod-usb-net kmod-usb-wdm kmod-usb-net-qmi-wwan kmod-wwan uqmi luci-proto-qmi \
kmod-usb-net-cdc-ether kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils \
kmod-usb-serial-qualcomm kmod-usb-acm kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim \
modemmanager  modemmanager-rpcd luci-proto-modemmanager libmbim libqmi usbutils luci-proto-mbim luci-proto-ncm \
kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-sierrawireless kmod-usb-ohci kmod-usb-serial-sierrawireless \
kmod-usb-uhci kmod-usb2 kmod-usb-ehci kmod-usb-net-ipheth usbmuxd libusbmuxd-utils libimobiledevice-utils usb-modeswitch kmod-nls-utf8 mbim-utils xmm-modem \
kmod-phy-broadcom kmod-phylib-broadcom kmod-tg3 libusb-1.0-0 kmod-usb3 kmod-r8169 kmod-lan743x picocom minicom kmod-usb-atm}"
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
    
        log_info "Preparing custom files from $source_path"
        local scripts=(
            "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/sbin/sync_time.sh|files/sbin"
            "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/usr/bin/clock|files/usr/bin"
            "https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh|files/root"
        )

        for script in "${scripts[@]}"; do
            IFS='|' read -r url path <<< "$script"
            mkdir -p "$path"
            wget --no-check-certificate -nv -P "$path" "$url" || error "Failed to download: $url"
        done
        
        # Set proper permissions for custom files
        find "$source_path" -type f -exec chmod 644 {} \;
        find "$source_path" -type d -exec chmod 755 {} \;
        
        # Make scripts executable
        find "$source_path" -name "*.sh" -exec chmod +x {} \;

        log_info "Copying custom files from $source_path"
        cp -r "$source_path" .
        
        log_success "Custom files prepared"
    else
        log_info "No custom files directory found at $source_path"
    fi
}

# Apply firmware-specific patches
apply_patches() {
    log_info "Applying firmware patches..."

    #sed -i "s/Ouc3kNF6/${DATE}/g" files/etc/uci-defaults/99-init-settings.sh

    sed -i 's|CONFIG_TARGET_KERNEL_PARTSIZE=.*|CONFIG_TARGET_KERNEL_PARTSIZE=128|' .config
    sed -i 's|CONFIG_TARGET_ROOTFS_PARTSIZE=.*|CONFIG_TARGET_ROOTFS_PARTSIZE=1024|' .config
    
    case "$BASE" in
        "openwrt")
            log_info "Applied OpenWrt cpufreq patch"
            #sed -i '/# setup misc settings/ a\mv \/www\/luci-static\/resources\/view\/status\/include\/29_temp.js \/www\/luci-static\/resources\/view\/status\/include\/17_temp.js' files/etc/uci-defaults/99-init-settings.sh
            ;;
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
            local configs=(
                CONFIG_TARGET_ROOTFS_CPIOGZ
                CONFIG_TARGET_ROOTFS_EXT4FS
                CONFIG_TARGET_ROOTFS_SQUASHFS
                CONFIG_TARGET_IMAGES_GZIP
            )

            for config in "${configs[@]}"; do
                sed -i "s|${config}=.*|# ${config} is not set|" .config 2>/dev/null
            done
            # rm -f files/etc/uci-defaults/70-rootpt-resize
            # rm -f files/etc/uci-defaults/80-rootfs-resize
            # rm -f files/etc/sysupgrade.conf
            ;;
        "x86-64")
            log_info "Applying x86-64 specific configurations..."
            sed -i 's|CONFIG_ISO_IMAGES=y|# CONFIG_ISO_IMAGES is not set|' .config 2>/dev/null
            sed -i 's|CONFIG_VHDX_IMAGES=y|# CONFIG_VHDX_IMAGES is not set|' .config 2>/dev/null
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
    mapfile -t image_files < <(find bin/targets -type f \( -name "*.img.gz" -o -name "*.bin" -o -name "*.vmdk" -o -name "*.img" \) 2>/dev/null)
    
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
    mapfile -t other_files < <(find bin/targets -type f \( -name "*.buildinfo" -o -name "*.manifest" \) 2>/dev/null)
    
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