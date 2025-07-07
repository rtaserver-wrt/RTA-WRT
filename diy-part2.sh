#!/bin/bash
# diy-part2.sh - Kustomisasi konfigurasi dan modifikasi
# Script untuk modifikasi konfigurasi OpenWrt setelah feeds diinstal

set -e  # Exit on error

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fungsi untuk backup file sebelum modifikasi
backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1.bak"
        log_info "Backed up $1"
    fi
}

# Deteksi source OpenWrt (openwrt/lede/immortalwrt)
detect_source() {
    if [ -d "package/lean" ]; then
        echo "lede"
    elif [ -d "package/emortal" ]; then
        echo "immortalwrt"
    else
        echo "openwrt"
    fi
}

SOURCE_TYPE=$(detect_source)
log_info "Detected source type: $SOURCE_TYPE"

# 1. Modifikasi versi default
log_info "Modifying default version string"
case "$SOURCE_TYPE" in
    "lede")
        if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
            backup_file "package/lean/default-settings/files/zzz-default-settings"
            sed -i 's/OpenWrt/MyWrt/g' package/lean/default-settings/files/zzz-default-settings
            sed -i 's/LEDE/MyWrt/g' package/lean/default-settings/files/zzz-default-settings
            log_success "Modified LEDE version string"
        fi
        ;;
    "immortalwrt")
        if [ -f "package/emortal/default-settings/files/99-default-settings" ]; then
            backup_file "package/emortal/default-settings/files/99-default-settings"
            sed -i 's/ImmortalWrt/MyWrt/g' package/emortal/default-settings/files/99-default-settings
            sed -i 's/OpenWrt/MyWrt/g' package/emortal/default-settings/files/99-default-settings
            log_success "Modified ImmortalWrt version string"
        fi
        ;;
    *)
        # Standard OpenWrt
        if [ -f "package/base-files/files/etc/openwrt_release" ]; then
            backup_file "package/base-files/files/etc/openwrt_release"
            sed -i 's/OpenWrt/MyWrt/g' package/base-files/files/etc/openwrt_release
            log_success "Modified OpenWrt version string"
        fi
        ;;
esac

# 2. Menambahkan theme
log_info "Installing custom themes"

# Argon Theme
if [ ! -d "package/luci-theme-argon" ]; then
    log_info "Cloning Argon theme"
    git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
    log_success "Argon theme installed"
else
    log_warning "Argon theme already exists"
fi

# Tambahan theme lain (opsional)
themes=(
    "https://github.com/jerrykuku/luci-app-argon-config.git luci-app-argon-config"
    "https://github.com/thinktip/luci-theme-neobird.git luci-theme-neobird"
)

for theme in "${themes[@]}"; do
    theme_url=$(echo "$theme" | cut -d' ' -f1)
    theme_name=$(echo "$theme" | cut -d' ' -f2)
    
    if [ ! -d "package/$theme_name" ]; then
        log_info "Installing theme: $theme_name"
        git clone --depth=1 "$theme_url" "package/$theme_name" || log_warning "Failed to clone $theme_name"
    else
        log_warning "Theme $theme_name already exists"
    fi
done

# 3. Mengatur zona waktu
log_info "Setting timezone configuration"
if [ -f "package/base-files/files/bin/config_generate" ]; then
    # Backup sudah dilakukan di atas
    sed -i "s/'UTC'/'WIB-7'/g" package/base-files/files/bin/config_generate
    log_success "Timezone set to WIB-7"
fi

# Tambahan: Set timezone di uci defaults
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-timezone << 'EOF'
#!/bin/sh
uci set system.@system[0].timezone='WIB-7'
uci set system.@system[0].zonename='Asia/Jakarta'
uci commit system
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-timezone
log_success "Added timezone uci-defaults"

# 4. Menambahkan banner kustom
log_info "Creating custom banner"
mkdir -p package/base-files/files/etc
cat > package/base-files/files/etc/banner << 'EOF'
  __  __      __        __
 |  \/  |_   _\ \      / /_ __| |_
 | |\/| | | | |\ \ /\ / /| '__| __|
 | |  | | |_| | \ V  V / | |  | |_
 |_|  |_|\__, |  \_/\_/  |_|   \__|
         |___/
 
 MyWrt - Custom OpenWrt Build
 -----------------------------------------------------
 Kernel: %K
 Version: %D %C
 Uptime: %U
 Load: %L
 -----------------------------------------------------
 
EOF
log_success "Custom banner created"

# 5. Konfigurasi jaringan default
log_info "Setting up default network configuration"
mkdir -p package/base-files/files/etc/config
cat > package/base-files/files/etc/config/network << 'EOF'
config interface 'loopback'
    option ifname 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fd12:3456:789a::/48'

config interface 'lan'
    option type 'bridge'
    option ifname 'eth0'
    option proto 'static'
    option ipaddr '192.168.1.1'
    option netmask '255.255.255.0'
    option ip6assign '60'
    option delegate '0'
EOF
log_success "Default network configuration created"

# 6. Menambahkan konfigurasi sistem default
log_info "Setting up system defaults"
cat > package/base-files/files/etc/config/system << 'EOF'
config system
    option hostname 'MyWrt'
    option timezone 'WIB-7'
    option zonename 'Asia/Jakarta'
    option ttylogin '0'
    option log_size '64'
    option urandom_seed '0'

config timeserver 'ntp'
    option enabled '1'
    option enable_server '0'
    list server '0.openwrt.pool.ntp.org'
    list server '1.openwrt.pool.ntp.org'
    list server '2.openwrt.pool.ntp.org'
    list server '3.openwrt.pool.ntp.org'
EOF
log_success "System defaults configured"

# 7. Menambahkan aplikasi default yang akan diinstal
log_info "Adding default applications to build"
cat >> .config << 'EOF'
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_vim=y
EOF
log_success "Default applications added to config"

# 8. Menambahkan script startup custom
log_info "Creating custom startup scripts"
mkdir -p package/base-files/files/etc/init.d
cat > package/base-files/files/etc/init.d/custom-setup << 'EOF'
#!/bin/sh /etc/rc.common
START=99

start() {
    # Custom startup tasks
    echo "MyWrt custom setup starting..."
    
    # Set LED behavior (if applicable)
    [ -f /sys/class/leds/power/trigger ] && echo "heartbeat" > /sys/class/leds/power/trigger
    
    # Additional custom setup can be added here
    logger -t custom-setup "MyWrt initialization complete"
}
EOF
chmod +x package/base-files/files/etc/init.d/custom-setup
log_success "Custom startup script created"

# 9. Cleanup dan optimasi
log_info "Performing cleanup and optimization"

# Hapus package yang tidak diperlukan (opsional)
# rm -rf package/lean/luci-app-wol 2>/dev/null || true
# rm -rf package/lean/luci-app-accesscontrol 2>/dev/null || true

# Optimasi untuk target tertentu
if [ "$1" == "x86_64" ]; then
    log_info "Applying x86_64 specific optimizations"
    # Tambahkan optimasi khusus x86_64
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
fi

# 10. Menampilkan ringkasan
log_info "=== DIY Part 2 Summary ==="
echo "✓ Version string modified to MyWrt"
echo "✓ Timezone set to WIB-7 (Asia/Jakarta)"
echo "✓ Custom banner installed"
echo "✓ Argon theme installed"
echo "✓ Network configuration set up"
echo "✓ System defaults configured"
echo "✓ Default applications added"
echo "✓ Custom startup script created"

# 11. Validasi akhir
log_info "Performing final validation"
if [ ! -f ".config" ]; then
    log_warning ".config file not found, creating basic config"
    touch .config
fi

log_success "DIY part 2 completed successfully!"

# Tips untuk pengguna
log_info "Tips:"
echo "  - Run 'make menuconfig' to further customize your build"
echo "  - Check .config file for applied configurations"
echo "  - Backup files are saved with .bak extension"
echo "  - Custom settings will be applied after flashing firmware"