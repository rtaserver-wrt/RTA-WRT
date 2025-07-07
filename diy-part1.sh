#!/bin/bash
# diy-part1.sh - Kustomisasi feeds dan tambahan repository
# Script untuk menambahkan feed tambahan ke OpenWrt

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

# Backup feeds.conf.default
if [ -f "feeds.conf.default" ]; then
    log_info "Backing up original feeds.conf.default"
    cp feeds.conf.default feeds.conf.default.bak
else
    log_warning "feeds.conf.default not found, creating new one"
    touch feeds.conf.default
fi

log_info "Adding custom feeds to feeds.conf.default"

# Array berisi feed yang akan ditambahkan
declare -a feeds=(
    "src-git passwall https://github.com/xiaorouji/openwrt-passwall"
    "src-git passwallpackages https://github.com/xiaorouji/openwrt-passwall-packages"
    "src-git openclash https://github.com/vernesong/OpenClash"
)

# Menambahkan feeds satu per satu dengan validasi
for feed in "${feeds[@]}"; do
    feed_name=$(echo "$feed" | cut -d' ' -f2)
    feed_url=$(echo "$feed" | cut -d' ' -f3)
    
    # Cek apakah feed sudah ada
    if grep -q "src-git $feed_name" feeds.conf.default; then
        log_warning "Feed '$feed_name' already exists, skipping"
        continue
    fi
    
    log_info "Adding feed: $feed_name"
    echo "$feed" >> feeds.conf.default
    
    # Validasi URL (basic check)
    if [[ ! "$feed_url" =~ ^https://github\.com/ ]]; then
        log_warning "Feed URL might be invalid: $feed_url"
    fi
done

# Menambahkan feed custom yang mungkin diperlukan berdasarkan target
if [ ! -z "$1" ]; then
    case "$1" in
        "x86_64")
            log_info "Adding x86_64 specific feeds"
            ;;
        "ramips_mt7621")
            log_info "Adding ramips specific feeds"
            ;;
        "bcm27xx_bcm2711")
            log_info "Adding Raspberry Pi specific feeds"
            ;;
    esac
fi

# Menghapus feed yang mungkin konflik (opsional)
log_info "Cleaning up conflicting feeds (if any)"
# Contoh: menghapus feed yang bermasalah
# sed -i '/src-git problematic_feed/d' feeds.conf.default

# Menambahkan konfigurasi tambahan
log_info "Adding additional configurations"

# Membuat direktori untuk file konfigurasi custom jika belum ada
mkdir -p files/etc/config

# Menambahkan konfigurasi network default (opsional)
if [ ! -f "files/etc/config/network" ]; then
    cat > files/etc/config/network << 'EOF'
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
EOF
    log_success "Created default network configuration"
fi

# Menampilkan hasil akhir
log_info "Final feeds.conf.default content:"
echo "----------------------------------------"
cat feeds.conf.default
echo "----------------------------------------"

# Validasi bahwa file feeds.conf.default valid
if [ ! -s "feeds.conf.default" ]; then
    log_error "feeds.conf.default is empty!"
    exit 1
fi

# Menghitung jumlah feed yang ditambahkan
total_feeds=$(grep -c "src-git" feeds.conf.default)
log_success "Successfully configured $total_feeds feeds"

# Membuat summary
log_info "Summary of added feeds:"
grep "src-git" feeds.conf.default | while read -r line; do
    feed_name=$(echo "$line" | cut -d' ' -f2)
    feed_url=$(echo "$line" | cut -d' ' -f3)
    echo "  - $feed_name: $feed_url"
done

log_success "diy-part1.sh completed successfully!"

# Menampilkan tips untuk troubleshooting
log_info "Tips:"
echo "  - If build fails, check if all feed URLs are accessible"
echo "  - Some feeds might conflict with each other"
echo "  - Use 'make menuconfig' to configure packages from new feeds"
echo "  - Backup files are saved with .bak extension"