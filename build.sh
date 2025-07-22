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

# Unicode icons for visual feedback
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
init_logging() {
    readonly LOG_FILE="${WORK_DIR}/build.log"
    exec > >(tee -a "${LOG_FILE}") 2>&1
}

log() {
    local level=$1 color=$2 icon=$3
    shift 3
    echo -e "${color}${icon}[$level]$(date '+%Y-%m-%d %H:%M:%S')${NC} $*" >&2
}

log_info() { log "INFO" "$BLUE" "$ICON_INFO" "$@"; }
log_success() { log "SUCCESS" "$GREEN" "$ICON_SUCCESS" "$@"; }
log_warn() { log "WARN" "$YELLOW" "$ICON_WARN" "$@"; }
log_error() { log "ERROR" "$RED" "$ICON_ERROR" "$@"; }
log_build() { log "BUILD" "$PURPLE" "$ICON_BUILD" "$@"; }
log_step() { log "STEP" "$CYAN" "$ICON_GEAR" "$@"; }

# ═══════════════════════════════════════════════════════════════════════════════
# 🛡️ ERROR HANDLING
# ═══════════════════════════════════════════════════════════════════════════════
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with error (code: $exit_code)"
        log_error "Check the log file for details: ${LOG_FILE}"
    fi
    exit $exit_code
}

error_handler() {
    local line_no=$1
    log_error "Build failed at line: $line_no"
    log_error "Working directory: $(pwd)"
    exit 1
}

trap 'error_handler $LINENO' ERR
trap cleanup EXIT
trap 'log_error "User interrupted build"; exit 1' SIGINT

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 DEPENDENCY CHECK
# ═══════════════════════════════════════════════════════════════════════════════
check_dependencies() {
    log_step "Checking system dependencies"
    
    local missing=()
    local required=("wget" "curl" "jq" "tar" "make" "find" "grep" "sed")
    
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        exit 1
    fi
    
    # Check for zstd support
    if ! tar --help | grep -q zstd; then
        log_error "tar does not support zstd compression. Install zstd or use a newer version of tar."
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# ═══════════════════════════════════════════════════════════════════════════════
# ⚙️ CONFIGURATION VARIABLES
# ═══════════════════════════════════════════════════════════════════════════════
# Default configuration
WORK_DIR="${OPENWRT_WORK_DIR:-${PWD}/openwrt-build}"
BASE="${1:-openwrt}"
BRANCH="${2:-24.10.2}"
TARGET_SYSTEM="${3:-x86/64}"
TARGET_NAME="${4:-x86-64}"
PROFILE="${5:-generic}"
ARCH="${6:-x86_64}"
PACKAGES_INCLUDE="${7:-}"
PACKAGES_EXCLUDE="${8:-}"
CLEAN_BUILD="${9:-0}"
VERSION="${10:-stable}"
CUSTOM_FILES_DIR="files"
JOBS="$(nproc)"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-0}"

# Default packages (consolidated to remove duplicates)
readonly DEFAULT_PACKAGES="
dnsmasq-full cgi-io libiwinfo libiwinfo-data libiwinfo-lua liblua \
luci-base luci-lib-base luci-lib-ip luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
cpusage ttyd dmesg kmod-tun luci-lib-ipkg git git-http \
zram-swap adb parted losetup resize2fs luci luci-ssl block-mount htop bash curl wget-ssl \
tar unzip unrar gzip jq luci-app-ttyd nano httping screen openssh-sftp-server \
liblucihttp liblucihttp-lua libubus-lua luci-app-firewall luci-app-opkg \
ca-bundle ca-certificates luci-compat coreutils-sleep fontconfig coreutils-whoami file lolcat \
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
kmod-usb-net-huawei-cdc-ncm kmod-usb-net-rndis kmod-usb-net-sierrawireless \
kmod-usb-ohci kmod-usb-serial-sierrawireless kmod-usb-uhci kmod-usb2 kmod-usb-ehci \
kmod-usb-net-ipheth usbmuxd libusbmuxd-utils libimobiledevice-utils usb-modeswitch kmod-nls-utf8 \
mbim-utils kmod-phy-broadcom kmod-phylib-broadcom kmod-tg3 libusb-1.0-0 kmod-usb3 \
kmod-r8169 kmod-lan743x picocom minicom kmod-usb-atm sms-tool python3-speedtest-cli"
readonly DEFAULT_REMOVED_PACKAGES="-dnsmasq"

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 PARAMETER VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════
validate_parameters() {
    log_step "Validating build parameters"

    # Validate base firmware
    if [[ ! "$BASE" =~ ^(openwrt|immortalwrt)$ ]]; then
        log_error "Unsupported base: $BASE. Use 'openwrt' or 'immortalwrt'"
        exit 1
    fi
    log_info "Base firmware: $BASE"

    # Validate branch format
    if [[ ! "$BRANCH" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        log_warn "Branch format unusual: $BRANCH (expected format: X.Y.Z)"
    fi

    # Validate target system format
    if [[ ! "$TARGET_SYSTEM" =~ ^[a-z0-9_-]+/[a-z0-9_-]+$ ]]; then
        log_warn "TARGET_SYSTEM format unusual: $TARGET_SYSTEM (expected: arch/subarch)"
    fi

    # Validate architecture
    if [[ ! "$ARCH" =~ ^[a-z0-9_]+$ ]]; then
        log_warn "Invalid architecture format: $ARCH"
    fi

    # Validate working directory
    if ! mkdir -p "$WORK_DIR" 2>/dev/null; then
        log_error "Cannot create or write to working directory: $WORK_DIR"
        exit 1
    fi

    log_success "Parameters validated"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🏗️ ENVIRONMENT SETUP
# ═══════════════════════════════════════════════════════════════════════════════
setup_environment() {
    log_step "Setting up build environment"

    # Display configuration
    log_info "Configuration:"
    log_info "  Working Directory: $WORK_DIR"
    log_info "  Base Firmware: $BASE"
    log_info "  Version Branch: $BRANCH"
    log_info "  Target System: $TARGET_SYSTEM"
    log_info "  Target Name: $TARGET_NAME"
    log_info "  Profile: $PROFILE"
    log_info "  Architecture: $ARCH"
    log_info "  Parallel Jobs: $JOBS"
    log_info "  Log File: $LOG_FILE"

    # Create and enter working directory
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR" || {
        log_error "Failed to change to working directory: $WORK_DIR"
        exit 1
    }

    # Clean build directory if requested
    if [[ "$CLEAN_BUILD" == "1" ]]; then
        log_info "${ICON_CLEAN}Cleaning previous build artifacts"
        rm -rf ./* 2>/dev/null || true
        log_success "Build directory cleaned"
    fi

    log_success "Environment setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📥 IMAGE BUILDER DOWNLOAD
# ═══════════════════════════════════════════════════════════════════════════════
download_imagebuilder() {
    log_step "${ICON_DOWNLOAD}Downloading Image Builder"

    local url="https://downloads.${BASE}.org/releases/$BRANCH/targets/$TARGET_SYSTEM/${BASE}-imagebuilder-$BRANCH-$TARGET_NAME.Linux-x86_64.tar.zst"
    local ib_file=$(basename "$url")

    # Check if file exists and force download is not set
    if [[ -f "$ib_file" && "$FORCE_DOWNLOAD" != "1" ]]; then
        log_info "Image builder already exists: $ib_file"
    else
        log_info "Downloading from: $url"
        
        # Use aria2c if available, otherwise fallback to wget
        if command -v aria2c &>/dev/null; then
            if ! aria2c -x16 -s16 -c "$url"; then
                log_error "Failed to download with aria2c, trying wget..."
                if ! wget -q --show-progress "$url"; then
                    log_error "Failed to download Image Builder from: $url"
                    exit 1
                fi
            fi
        else
            if ! wget -q --show-progress "$url"; then
                log_error "Failed to download Image Builder from: $url"
                exit 1
            fi
        fi
        log_success "Download completed: $ib_file"
    fi

    # Verify file integrity
    if [[ ! -s "$ib_file" ]]; then
        log_error "Downloaded file is empty or corrupted: $ib_file"
        exit 1
    fi

    # Extract archive
    log_info "${ICON_FILE}Extracting Image Builder archive"
    if ! tar -I zstd -xf "$ib_file" --strip-components=1; then
        log_error "Failed to extract Image Builder archive: $ib_file"
        exit 1
    fi

    log_success "Image Builder extracted and ready"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📁 CUSTOM PACKAGES PREPARATION
# ═══════════════════════════════════════════════════════════════════════════════
prepare_custom_packages() {
    log_step "${ICON_FILE}Preparing custom packages"

    mkdir -p packages

    local ver_op=$(echo "$BRANCH" | awk -F. '{print $1"."$2}')
    declare -A REPOS=(
        ["KIDDIN9"]="https://dl.openwrt.ai/releases/${ver_op}/packages/${ARCH}/kiddin9"
        ["IMMORTALWRT"]="https://downloads.immortalwrt.org/releases/packages-${ver_op}/${ARCH}"
        ["OPENWRT"]="https://downloads.openwrt.org/releases/packages-${ver_op}/${ARCH}"
        ["GSPOTX2F"]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
        ["FANTASTIC"]="https://fantastic-packages.github.io/packages/releases/${ver_op}/packages/mipsel_24kc"
    )
    declare -A custom_packages=(
        ["luci-app-advanced-reboot"]="https://downloads.openwrt.org/releases/packages-${ver_op}/${ARCH}/luci"
        ["luci-app-netmonitor"]="https://api.github.com/repos/rizkikotet-dev/luci-app-netmonitor/releases/latest"

        # KIDDIN9 packages
        ["luci-app-tailscale"]="${REPOS[KIDDIN9]}"
        ["luci-app-diskman"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-zte"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-gosun"]="${REPOS[KIDDIN9]}"
        ["modeminfo-qmi"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-yuge"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-thales"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-tw"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-meig"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-styx"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-mikrotik"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-dell"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-sierra"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-quectel"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-huawei"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-xmm"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-telit"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-fibocom"]="${REPOS[KIDDIN9]}"
        ["modeminfo-serial-simcom"]="${REPOS[KIDDIN9]}"
        ["modeminfo"]="${REPOS[KIDDIN9]}"
        ["luci-app-modeminfo"]="${REPOS[KIDDIN9]}"
        ["atinout"]="${REPOS[KIDDIN9]}"
        ["luci-app-poweroffdevice"]="${REPOS[KIDDIN9]}"
        ["xmm-modem"]="${REPOS[KIDDIN9]}"
        ["luci-app-lite-watchdog"]="${REPOS[KIDDIN9]}"
        ["luci-theme-alpha"]="${REPOS[KIDDIN9]}"
        ["luci-app-adguardhome"]="${REPOS[KIDDIN9]}"
        ["sing-box"]="${REPOS[KIDDIN9]}"
        ["mihomo"]="${REPOS[KIDDIN9]}"
        ["luci-app-droidmodem"]="${REPOS[KIDDIN9]}"

        # IMMORTALWRT packages
        ["luci-app-zerotier"]="${REPOS[IMMORTALWRT]}/luci"
        ["luci-app-ramfree"]="${REPOS[IMMORTALWRT]}/luci"
        ["luci-app-3ginfo-lite"]="${REPOS[IMMORTALWRT]}/luci"
        ["modemband"]="${REPOS[IMMORTALWRT]}/packages"
        ["luci-app-modemband"]="${REPOS[IMMORTALWRT]}/luci"
        ["luci-app-sms-tool-js"]="${REPOS[IMMORTALWRT]}/luci"
        ["dns2tcp"]="${REPOS[IMMORTALWRT]}/packages"
        ["luci-app-argon-config"]="${REPOS[IMMORTALWRT]}/luci"
        ["luci-theme-argon"]="${REPOS[IMMORTALWRT]}/luci"
        ["luci-app-openclash"]="${REPOS[IMMORTALWRT]}/luci"
        ["luci-app-passwall"]="${REPOS[IMMORTALWRT]}/luci"

        # GSPOTX2F packages
        ["luci-app-internet-detector"]="${REPOS[GSPOTX2F]}"
        ["internet-detector"]="${REPOS[GSPOTX2F]}"
        ["internet-detector-mod-modem-restart"]="${REPOS[GSPOTX2F]}"
        ["luci-app-cpu-status-mini"]="${REPOS[GSPOTX2F]}"
        ["luci-app-disks-info"]="${REPOS[GSPOTX2F]}"
        ["luci-app-log-viewer"]="${REPOS[GSPOTX2F]}"
        ["luci-app-temp-status"]="${REPOS[GSPOTX2F]}"

        # FANTASTIC packages
        ["luci-app-netspeedtest"]="${REPOS[FANTASTIC]}/luci"
    )

    for pkg_name in "${!custom_packages[@]}"; do
        local base_url="${custom_packages[$pkg_name]}"
        log_info "Processing package: $pkg_name"

        local download_url=""
        if [[ "$base_url" == *"api.github.com"* ]]; then
            # Handle GitHub API download
            log_info "Fetching GitHub release info for $pkg_name"
            response=$(curl -s "$base_url")
            download_url=$(echo "$response" | grep "browser_download_url" | grep -E "\.ipk|\.apk" | cut -d '"' -f 4 | head -n 1)
        else
            # Try fetching .ipk or .apk
            for ext in ipk apk; do
                temp_url="$base_url/${pkg_name}*.$ext"
                files=$(wget -qO- "$base_url/" | grep -oP "${pkg_name}[-_].*?\.${ext}" | head -n 1)
                [[ -n "$files" ]] && download_url="${base_url}/${files}" && break
            done
        fi

        if [[ -z "$download_url" || "$download_url" == "null" ]]; then
            log_error "Failed to get download URL for $pkg_name"
            continue
        fi

        log_info "Downloading package: $pkg_name from $download_url"
        if ! wget --no-check-certificate -nv -P packages/ "$download_url"; then
            log_error "Failed to download package: $pkg_name"
            continue
        fi
        log_success "Package downloaded: $pkg_name"
    done

    # Copy external packages from ../packages if exist
    if [[ -d "../packages" ]]; then
        log_info "Copying external packages"
        local copied_count=0 failed_count=0

        for ext_pkg in ../packages/*; do
            [[ -f "$ext_pkg" ]] || continue
            if cp "$ext_pkg" packages/ 2>/dev/null; then
                ((copied_count++))
            else
                ((failed_count++))
            fi
        done

        [[ $copied_count -gt 0 ]] && log_success "Copied $copied_count external packages"
        [[ $failed_count -gt 0 ]] && log_warn "$failed_count external packages failed to copy"
    fi

    # Add downloaded packages to include list
    local added_count=0
    for list_pkg in "${!custom_packages[@]}"; do
        shopt -s nullglob
        found_files=(packages/${list_pkg}*.ipk packages/${list_pkg}*.apk)
        if (( ${#found_files[@]} )); then
            PACKAGES_INCLUDE="${PACKAGES_INCLUDE} ${list_pkg}"
            log_info "Added custom package to include list: $list_pkg"
            ((added_count++))
        else
            log_warn "No matching package file found, skipping: $list_pkg"
        fi
        shopt -u nullglob
    done

    log_success "Custom packages preparation completed - $added_count packages added to include list"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📁 CUSTOM FILES PREPARATION
# ═══════════════════════════════════════════════════════════════════════════════
prepare_custom_files() {
    log_step "${ICON_FILE}Preparing custom files"

    local source_path="../$CUSTOM_FILES_DIR"
    local scripts=(
        "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/sbin/sync_time.sh|files/sbin"
        "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/usr/bin/clock|files/usr/bin"
        "https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh|files/root"
    )

    # Download scripts
    for script in "${scripts[@]}"; do
        IFS='|' read -r url path <<< "$script"
        log_info "Downloading: $(basename "$url")"
        mkdir -p "$path"
        if ! wget --no-check-certificate -nv -O "${path}/$(basename "$url")" "$url"; then
            log_warn "Failed to download: $url"
        fi
    done

    # Copy custom files
    if [[ -d "$source_path" ]]; then
        log_info "Copying custom files from: $source_path"
        if ! cp -r "$source_path" .; then
            log_warn "Some custom files failed to copy"
        fi

        # Set permissions
        log_info "Setting file permissions"
        find "$CUSTOM_FILES_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
        find "$CUSTOM_FILES_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
        find "$CUSTOM_FILES_DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
        log_success "Custom files prepared successfully"
    else
        log_info "No custom files directory found at: $source_path"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 FIRMWARE PATCHES APPLICATION
# ═══════════════════════════════════════════════════════════════════════════════
apply_patches() {
    log_step "${ICON_GEAR}Applying firmware patches"

    # Configure partition sizes
    if [[ -f ".config" ]]; then
        log_info "Configuring partition sizes"
        sed -i 's|CONFIG_TARGET_KERNEL_PARTSIZE=.*|CONFIG_TARGET_KERNEL_PARTSIZE=128|' .config
        sed -i 's|CONFIG_TARGET_ROOTFS_PARTSIZE=.*|CONFIG_TARGET_ROOTFS_PARTSIZE=1024|' .config
        log_success "Partition sizes configured (Kernel: 128MB, RootFS: 1024MB)"
    fi

    # Base-specific patches
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
            if [[ -f ".config" ]]; then
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
            fi
            ;;
        "x86-64")
            if [[ -f ".config" ]]; then
                log_info "Configuring x86-64 specific settings"
                sed -i 's|CONFIG_ISO_IMAGES=y|# CONFIG_ISO_IMAGES is not set|' .config 2>/dev/null || true
                sed -i 's|CONFIG_VHDX_IMAGES=y|# CONFIG_VHDX_IMAGES is not set|' .config 2>/dev/null || true
                log_success "x86-64 configurations applied"
            fi
            ;;
    esac

    # Optimize build process
    if [[ -f "repositories.conf" ]]; then
        log_info "Disabling package signature checks for faster builds"
        sed -i '\|option check_signature| s|^|#|' repositories.conf
        log_success "Package signature checking disabled"
    fi

    log_success "All patches applied successfully"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔨 FIRMWARE BUILD PROCESS
# ═══════════════════════════════════════════════════════════════════════════════
build_firmware() {
    log_step "${ICON_BUILD}Starting firmware build process"

    # Construct package list
    local package_list="$DEFAULT_PACKAGES $DEFAULT_REMOVED_PACKAGES $PACKAGES_INCLUDE $PACKAGES_EXCLUDE"
    local included_count=$(echo "$package_list" | tr ' ' '\n' | grep -v '^-' | sort -u | wc -l)
    local excluded_count=$(echo "$package_list" | tr ' ' '\n' | grep '^-' | sort -u | wc -l)
    log_info "Included packages: $included_count unique packages"
    log_info "Excluded packages: $excluded_count unique packages"

    # Build make command
    local make_cmd="make image PROFILE=\"$PROFILE\" PACKAGES=\"$package_list\""
    [[ -d "$CUSTOM_FILES_DIR" ]] && make_cmd+=" FILES=\"$CUSTOM_FILES_DIR\""
    make_cmd+=" -j$JOBS"

    log_build "Executing build command with $JOBS parallel jobs"
    local start_time=$(date +%s)
    log_info "Build started at: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Build command: $make_cmd"

    if ! eval "$make_cmd"; then
        log_error "Build failed! Check output for details."
        log_info "Common solutions:"
        log_info "  • Check internet connection"
        log_info "  • Verify package names in PACKAGES_INCLUDE"
        log_info "  • Ensure sufficient disk space (minimum 10GB recommended)"
        log_info "  • Try with CLEAN_BUILD=1"
        log_info "  • Check the log file: $LOG_FILE"
        exit 1
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "Build completed in $((duration / 60))m $((duration % 60))s"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 BUILD RESULTS DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════
show_results() {
    log_step "Displaying build results"

    local image_files
    mapfile -t image_files < <(find bin/targets -type f \( -name "*.img.gz" -o -name "*.bin" -o -name "*.vmdk" -o -name "*.img" \) 2>/dev/null)

    if [[ ${#image_files[@]} -eq 0 ]]; then
        log_warn "No firmware images found in bin/targets"
        find bin/targets -type f 2>/dev/null || log_warn "bin/targets directory not found"
    else
        log_info "Firmware images generated:"
        printf "${WHITE}%-50s %10s %20s${NC}\n" "Filename" "Size" "Modified"
        printf "${BLUE}%-80s${NC}\n" | tr ' ' '─'
        for file in "${image_files[@]}"; do
            local size=$(du -h "$file" | cut -f1)
            local modified=$(date -r "$file" '+%Y-%m-%d %H:%M:%S')
            printf "${GREEN}%-50s${NC} ${YELLOW}%10s${NC} ${CYAN}%20s${NC}\n" "$(basename "$file")" "$size" "$modified"
        done
        log_success "Generated ${#image_files[@]} firmware image(s)"
        log_info "Images location: $(pwd)/bin/targets"
    fi

    local other_files
    mapfile -t other_files < <(find bin/targets -type f \( -name "*.buildinfo" -o -name "*.manifest" \) 2>/dev/null)
    if [[ ${#other_files[@]} -gt 0 ]]; then
        log_info "Additional build artifacts:"
        for file in "${other_files[@]}"; do
            echo -e "  ${BLUE}•${NC} $(basename "$file")"
        done
    fi

    log_info "Build summary:"
    log_info "  Base: $BASE $BRANCH"
    log_info "  Target: $TARGET_SYSTEM ($PROFILE)"
    log_info "  Images Generated: ${#image_files[@]}"
    log_info "  Build Time: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "  Log File: $LOG_FILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN EXECUTION FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════
main() {
    init_logging
    log_info "RTA-WRT Image Builder Script"
    log_info "Starting build process..."

    check_dependencies
    validate_parameters
    setup_environment
    download_imagebuilder
    prepare_custom_packages
    prepare_custom_files
    apply_patches
    build_firmware
    show_results

    log_success "Script completed successfully!"
}

main "$@"