#!/bin/bash

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# 🎨 COLOR DEFINITIONS & ICONS
# ═══════════════════════════════════════════════════════════════════════════════
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Unicode icons for enhanced visual appeal
readonly ICON_INFO="ℹ️ "
readonly ICON_SUCCESS="✅"
readonly ICON_WARN="⚠️ "
readonly ICON_ERROR="❌"
readonly ICON_BUILD="🔨"
readonly ICON_DOWNLOAD="📦"
readonly ICON_ROCKET="🚀"
readonly ICON_GEAR="⚙️ "
readonly ICON_FILE="📁"
readonly ICON_TIME="⏱️ "
readonly ICON_CLEAN="🧹"

# ═══════════════════════════════════════════════════════════════════════════════
# 📝 LOGGING FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════
log_info() { 
    echo -e "${BLUE}${ICON_INFO}[INFO]${NC} $*"
}

log_success() { 
    echo -e "${GREEN}${ICON_SUCCESS}[SUCCESS]${NC} $*"
}

log_warn() { 
    echo -e "${YELLOW}${ICON_WARN}[WARN]${NC} $*"
}

log_error() { 
    echo -e "${RED}${ICON_ERROR}[ERROR]${NC} $*" >&2
}

log_build() {
    echo -e "${PURPLE}${ICON_BUILD}[BUILD]${NC} $*"
}

log_step() {
    echo -e "${CYAN}${ICON_GEAR}[STEP]${NC} $*"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🛡️  ERROR HANDLING
# ═══════════════════════════════════════════════════════════════════════════════
error_handler() {
    local line_no=$1
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}                    ${ICON_ERROR}BUILD FAILED${NC}                        ${RED}║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC} Script failed at line: ${WHITE}$line_no${NC}                          ${RED}║${NC}"
    echo -e "${RED}║${NC} Working directory: ${WHITE}$(pwd)${NC}           ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    exit 1
}
trap 'error_handler $LINENO' ERR

# ═══════════════════════════════════════════════════════════════════════════════
# ⚙️  CONFIGURATION VARIABLES
# ═══════════════════════════════════════════════════════════════════════════════
readonly WORK_DIR="${OPENWRT_WORK_DIR:-${PWD}/openwrt-build}"
readonly BASE="${1:-openwrt}"
readonly BRANCH="${2:-24.10.2}"
readonly TARGET_SYSTEM="${3:-x86/64}"
readonly TARGET_NAME="${4:-x86-64}"
readonly PROFILE="${5:-generic}"
readonly ARCH="${6:-x86_64}"

# 📦 Package configuration
readonly PACKAGES_INCLUDE="${7}"

readonly PACKAGES_EXCLUDE="${8}"
readonly CUSTOM_FILES_DIR="files"
readonly JOBS="$(nproc)"
readonly CLEAN_BUILD="${9:-0}"
readonly VERSION="${10:-stable}"


readonly DEFAULT_PACKAGES="dnsmasq-full cgi-io libiwinfo libiwinfo-data libiwinfo-lua liblua \
luci-base luci-lib-base luci-lib-ip luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
cpusage ttyd dmesg kmod-tun luci-lib-ipkg git git-http \
zram-swap adb parted losetup resize2fs luci luci-ssl block-mount htop bash curl wget-ssl \
tar unzip unrar gzip jq luci-app-ttyd nano httping screen openssh-sftp-server \
liblucihttp liblucihttp-lua libubus-lua lua luci-app-firewall luci-app-opkg \
ca-bundle ca-certificates luci-compat coreutils-sleep fontconfig coreutils-whoami file lolcat \
luci-base luci-lib-base luci-lib-ip luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
luci-mod-network luci-mod-status luci-mod-system luci-proto-ipv6 luci-proto-ppp \
luci-theme-bootstrap rpcd rpcd-mod-file rpcd-mod-iwinfo rpcd-mod-luci \
rpcd-mod-rrdns uhttpd uhttpd-mod-ubus coreutils coreutils-base64 coreutils-nohup coreutils-stty \
libc coreutils-stat coreutils-timeout ip-full libuci-lua microsocks resolveip ipset iptables \
iptables-legacy iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy kmod-ipt-nat \
luci-lua-runtime zoneinfo-asia zoneinfo-core perl perlbase-base perlbase-bytes perlbase-class \
perlbase-config perlbase-cwd perlbase-dynaloader perlbase-errno perlbase-essential perlbase-fcntl \
perlbase-file perlbase-filehandle perlbase-i18n perlbase-integer perlbase-io perlbase-list \
perlbase-locale perlbase-params perlbase-posix perlbase-re perlbase-scalar perlbase-selectsaver \
perlbase-socket perlbase-symbol perlbase-tie perlbase-time perlbase-unicore perlbase-utf8 \
perlbase-xsloader php8 php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo \
php8-mod-zip php8-mod-iconv php8-mod-mbstring luci-theme-material kmod-usb-net-rtl8150 \
kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179 kmod-mii kmod-usb-net \
kmod-usb-wdm kmod-usb-net-qmi-wwan kmod-wwan uqmi luci-proto-qmi kmod-usb-net-cdc-ether \
kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils kmod-usb-serial-qualcomm \
kmod-usb-acm kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim modemmanager modemmanager-rpcd \
luci-proto-modemmanager libmbim libqmi usbutils luci-proto-mbim luci-proto-ncm \
kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-sierrawireless \
kmod-usb-ohci kmod-usb-serial-sierrawireless kmod-usb-uhci kmod-usb2 kmod-usb-ehci \
kmod-usb-net-ipheth usbmuxd libusbmuxd-utils libimobiledevice-utils usb-modeswitch kmod-nls-utf8 \
mbim-utils kmod-phy-broadcom kmod-phylib-broadcom kmod-tg3 libusb-1.0-0 kmod-usb3 \
kmod-r8169 kmod-lan743x picocom minicom kmod-usb-atm"

readonly DEFAULT_REMOVED_PACKAGES="-dnsmasq"

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 PARAMETER VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════
validate_parameters() {
    log_step "Validating build parameters"
    
    case "$BASE" in
        openwrt|immortalwrt) 
            log_info "Base firmware: ${GREEN}$BASE${NC}"
            ;;
        *) 
            log_error "Unsupported base: $BASE. Use 'openwrt' or 'immortalwrt'"
            exit 1
            ;;
    esac
    
    if [[ ! "$BRANCH" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        log_warn "Branch format unusual: $BRANCH (expected format: X.Y.Z)"
    fi
    
    if [[ ! "$TARGET_SYSTEM" =~ ^[a-z0-9_-]+/[a-z0-9_-]+$ ]]; then
        log_warn "TARGET_SYSTEM format unusual: $TARGET_SYSTEM (expected: arch/subarch)"
    fi
    
    log_success "Parameters validated"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🏗️  ENVIRONMENT SETUP
# ═══════════════════════════════════════════════════════════════════════════════
setup_environment() {
    log_step "Setting up build environment"
    
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                    ${ICON_GEAR}BUILD CONFIGURATION${NC}                    ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Working Directory: ${WHITE}$WORK_DIR${NC}"
    echo -e "${CYAN}║${NC} Base Firmware:     ${WHITE}$BASE${NC}"
    echo -e "${CYAN}║${NC} Version Branch:    ${WHITE}$BRANCH${NC}"
    echo -e "${CYAN}║${NC} Target System:     ${WHITE}$TARGET_SYSTEM${NC}"
    echo -e "${CYAN}║${NC} Target Name:       ${WHITE}$TARGET_NAME${NC}"
    echo -e "${CYAN}║${NC} Profile:           ${WHITE}$PROFILE${NC}"
    echo -e "${CYAN}║${NC} Architecture:      ${WHITE}$ARCH${NC}"
    echo -e "${CYAN}║${NC} Parallel Jobs:     ${WHITE}$JOBS${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    # Create working directory with proper permissions
    log_info "Creating working directory: ${WORK_DIR}"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Clean previous builds if requested
    if [[ "${CLEAN_BUILD}" == "1" ]]; then
        log_info "${ICON_CLEAN}Cleaning previous build artifacts"
        rm -rf ./*
        log_success "Build directory cleaned"
    fi
    
    log_success "Environment setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📥 IMAGE BUILDER DOWNLOAD
# ═══════════════════════════════════════════════════════════════════════════════
download_imagebuilder() {
    log_step "${ICON_DOWNLOAD}Downloading Image Builder"
    
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
        log_info "Image builder already exists: ${GREEN}$ib_file${NC}"
    else
        log_info "Downloading from: ${BLUE}$url${NC}"
        if ! wget -q --show-progress "$url"; then
            log_error "Failed to download Image Builder"
            log_error "URL: $url"
            log_error "Please verify the URL is accessible and correct"
            exit 1
        fi
        log_success "Download completed: $ib_file"
    fi
    
    # Verify download integrity
    if [[ ! -f "$ib_file" ]] || [[ ! -s "$ib_file" ]]; then
        log_error "Downloaded file is missing or corrupted: $ib_file"
        exit 1
    fi
    
    log_info "${ICON_FILE}Extracting Image Builder archive"
    if ! tar -I zstd -xf "$ib_file" --strip-components=1; then
        log_error "Failed to extract Image Builder. Archive might be corrupted"
        exit 1
    fi
    
    log_success "Image Builder extracted and ready"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📁 CUSTOM PACKAGES PREPARATION
# ═══════════════════════════════════════════════════════════════════════════════
prepare_custom_packages() {
    log_step "${ICON_FILE}Preparing custom packages"
    
    bash scripts/2-download_packages.sh "$BASE" "$TARGET_NAME" "$VERSION"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📁 CUSTOM FILES PREPARATION
# ═══════════════════════════════════════════════════════════════════════════════
prepare_custom_files() {
    log_step "${ICON_FILE}Preparing custom files"
    
    local source_path="../$CUSTOM_FILES_DIR"
    
    if [[ -d "$source_path" ]]; then
        log_info "Found custom files directory: ${GREEN}$source_path${NC}"
        
        # Download additional scripts
        log_info "Downloading additional scripts"
        local scripts=(
            "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/sbin/sync_time.sh|files/sbin"
            "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/usr/bin/clock|files/usr/bin"
            "https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh|files/root"
        )

        for script in "${scripts[@]}"; do
            IFS='|' read -r url path <<< "$script"
            log_info "Downloading: $(basename "$url")"
            mkdir -p "$path"
            if ! wget --no-check-certificate -nv -P "$path" "$url"; then
                log_error "Failed to download: $url"
                exit 1
            fi
        done
        
        # Set proper permissions
        log_info "Setting file permissions"
        find "$source_path" -type f -exec chmod 644 {} \;
        find "$source_path" -type d -exec chmod 755 {} \;
        find "$source_path" -name "*.sh" -exec chmod +x {} \;

        log_info "Copying custom files"
        cp -r "$source_path" .
        
        log_success "Custom files prepared successfully"
    else
        log_info "No custom files directory found at: $source_path"
        log_info "Skipping custom files preparation"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 FIRMWARE PATCHES APPLICATION
# ═══════════════════════════════════════════════════════════════════════════════
apply_patches() {
    log_step "${ICON_GEAR}Applying firmware patches"
    
    # Apply kernel and rootfs size patches
    log_info "Configuring partition sizes"
    sed -i 's|CONFIG_TARGET_KERNEL_PARTSIZE=.*|CONFIG_TARGET_KERNEL_PARTSIZE=128|' .config
    sed -i 's|CONFIG_TARGET_ROOTFS_PARTSIZE=.*|CONFIG_TARGET_ROOTFS_PARTSIZE=1024|' .config
    log_success "Partition sizes configured (Kernel: 128MB, RootFS: 1024MB)"
    
    # Base-specific patches
    case "$BASE" in
        "openwrt")
            log_info "Applying OpenWrt specific patches"
            ;;
        "immortalwrt")
            if [[ -f "include/target.mk" ]]; then
                sed -i "/luci-app-cpufreq/d" include/target.mk
                log_info "Applied ImmortalWrt cpufreq patch"
            fi
            ;;
    esac
    
    # Target-specific configurations
    log_info "Applying target-specific configurations for: ${GREEN}$TARGET_NAME${NC}"
    case "$TARGET_NAME" in
        "armsr-armv8")
            log_info "Configuring ARM64 specific settings"
            local configs=(
                CONFIG_TARGET_ROOTFS_CPIOGZ
                CONFIG_TARGET_ROOTFS_EXT4FS
                CONFIG_TARGET_ROOTFS_SQUASHFS
                CONFIG_TARGET_IMAGES_GZIP
            )

            for config in "${configs[@]}"; do
                sed -i "s|${config}=.*|# ${config} is not set|" .config 2>/dev/null || true
            done
            log_success "ARM64 configurations applied"
            ;;
        "x86-64")
            log_info "Configuring x86-64 specific settings"
            sed -i 's|CONFIG_ISO_IMAGES=y|# CONFIG_ISO_IMAGES is not set|' .config 2>/dev/null || true
            sed -i 's|CONFIG_VHDX_IMAGES=y|# CONFIG_VHDX_IMAGES is not set|' .config 2>/dev/null || true
            log_success "x86-64 configurations applied"
            ;;
    esac
    
    # Optimize build process
    if [[ -f "repositories.conf" ]]; then
        log_info "Optimizing build process (disabling signature checks)"
        sed -i '\|option check_signature| s|^|#|' repositories.conf
        log_success "Package signature checking disabled for faster builds"
    fi
    
    log_success "All patches applied successfully"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔨 FIRMWARE BUILD PROCESS
# ═══════════════════════════════════════════════════════════════════════════════
build_firmware() {
    log_step "${ICON_BUILD}Starting firmware build process"
    
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}                     ${ICON_BUILD}BUILD DETAILS${NC}"
    echo -e "${PURPLE}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║${NC} Profile:      ${WHITE}$PROFILE${NC}"
    echo -e "${PURPLE}║${NC} Jobs:         ${WHITE}$JOBS parallel${NC}"
    echo -e "${PURPLE}║${NC} Custom Files: ${WHITE}$([ -d "$CUSTOM_FILES_DIR" ] && echo "Yes" || echo "No")${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    log_info "Included packages: ${GREEN}$(echo $PACKAGES_INCLUDE | wc -w) packages${NC}"
    log_info "Excluded packages: ${RED}$PACKAGES_EXCLUDE${NC}"
    
    # Build make command
    local make_cmd="make image"
    make_cmd+=" PROFILE=\"$PROFILE\""
    make_cmd+=" PACKAGES=\"$DEFAULT_PACKAGES $PACKAGES_INCLUDE $DEFAULT_REMOVED_PACKAGES $PACKAGES_EXCLUDE\""
    
    if [[ -d "$CUSTOM_FILES_DIR" ]]; then
        make_cmd+=" FILES=\"$CUSTOM_FILES_DIR\""
        log_info "Including custom files from: ${GREEN}$CUSTOM_FILES_DIR${NC}"
    fi
    
    make_cmd+=" -j$JOBS"
    
    log_build "Build command prepared"
    log_info "Starting build with ${GREEN}$JOBS${NC} parallel jobs"
    
    # Start build timer
    local start_time=$(date +%s)
    echo ""
    echo -e "${WHITE}${ICON_TIME}Build started at: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    
    if eval "$make_cmd"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        echo ""
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}                    ${ICON_SUCCESS}BUILD SUCCESSFUL${NC}"
        echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} Build completed in: ${WHITE}${minutes}m ${seconds}s${NC}"
        echo -e "${GREEN}║${NC} Total duration: ${WHITE}${duration} seconds${NC}}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    else
        log_error "Build failed! Check the output above for details"
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}  Common solutions:"
        echo -e "${RED}║${NC}  • Check internet connection"
        echo -e "${RED}║${NC}  • Verify package names in PACKAGES_INCLUDE"
        echo -e "${RED}║${NC}  • Ensure sufficient disk space"
        echo -e "${RED}║${NC}  • Try with CLEAN_BUILD=1"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 BUILD RESULTS DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════
show_results() {
    log_step "📊 Displaying build results"
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                    ${ICON_ROCKET}BUILD RESULTS${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    local image_files
    mapfile -t image_files < <(find bin/targets -type f \( -name "*.img.gz" -o -name "*.bin" -o -name "*.vmdk" -o -name "*.img" \) 2>/dev/null || true)
    
    if [[ ${#image_files[@]} -eq 0 ]]; then
        log_warn "No firmware images found in bin/targets"
        log_info "Checking for any files in bin/targets:"
        find bin/targets -type f 2>/dev/null || log_warn "bin/targets directory not found"
    else
        echo ""
        echo -e "${WHITE}📱 FIRMWARE IMAGES GENERATED:${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
        printf "${WHITE}%-50s %10s %20s${NC}\n" "Filename" "Size" "Modified"
        printf "${BLUE}%-80s${NC}\n" | tr ' ' '─'
        
        for file in "${image_files[@]}"; do
            local size=$(du -h "$file" | cut -f1)
            local modified=$(date -r "$file" '+%Y-%m-%d %H:%M:%S')
            printf "${GREEN}%-50s${NC} ${YELLOW}%10s${NC} ${CYAN}%20s${NC}\n" "$(basename "$file")" "$size" "$modified"
        done
        
        echo ""
        log_success "Generated ${GREEN}${#image_files[@]}${NC} firmware image(s)"
        log_info "📁 Images location: ${WHITE}$(pwd)/bin/targets${NC}"
    fi
    
    # Show additional artifacts
    local other_files
    mapfile -t other_files < <(find bin/targets -type f \( -name "*.buildinfo" -o -name "*.manifest" \) 2>/dev/null || true)
    
    if [[ ${#other_files[@]} -gt 0 ]]; then
        echo ""
        log_info "📄 Additional build artifacts:"
        for file in "${other_files[@]}"; do
            echo -e "  ${BLUE}•${NC} $(basename "$file")"
        done
    fi
    
    # Show summary statistics
    echo ""
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}                     ${ICON_GEAR}BUILD SUMMARY${NC}                        ${PURPLE}║${NC}"
    echo -e "${PURPLE}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║${NC} Base:             ${WHITE}$BASE $BRANCH${NC}"
    echo -e "${PURPLE}║${NC} Target:           ${WHITE}$TARGET_SYSTEM ($PROFILE)${NC}"
    echo -e "${PURPLE}║${NC} Images Generated: ${WHITE}${#image_files[@]}${NC}"
    echo -e "${PURPLE}║${NC} Build Time:       ${WHITE}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN EXECUTION FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════
main() {
    # Display banner
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}          ${ICON_ROCKET}${WHITE}RTA-WRT Image Builder Script${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Execute build steps
    validate_parameters
    setup_environment
    download_imagebuilder
    prepare_custom_packages
    prepare_custom_files
    apply_patches
    build_firmware
    show_results
    
    # Success message
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                ${ICON_SUCCESS}${WHITE}SCRIPT COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Execute main function with all arguments
main "$@"