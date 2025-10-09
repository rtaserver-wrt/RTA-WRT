#!/bin/sh
#
# RTA-WRT Router Setup Script v2.1
# Automated OpenWrt/ImmortalWrt router configuration
# https://github.com/rtaserver-wrt/RTA-WRT
#

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_VERSION="2.1"
LOGFILE="/root/setup_$(date +%Y%m%d_%H%M%S).log"
HOSTNAME="RTA-WRT"
LAN_IP="192.168.1.1"
LAN_NETMASK="255.255.255.0"
TIMEZONE="WIB-7"
ZONENAME="Asia/Jakarta"
ROOT_PASSWORD="rtawrt"
WIFI_2G_SSID="RTA-WRT_2G"
WIFI_5G_SSID="RTA-WRT_5G"

# ============================================================================
# LOGGING SETUP
# ============================================================================

exec > >(tee -a "$LOGFILE") 2>&1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local color="$NC"
    
    case "$level" in
        INFO) color="$GREEN" ;;
        WARN) color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        STEP) color="$BLUE" ;;
        DEBUG) color="$CYAN" ;;
    esac
    
    printf "${color}[%s] [%s] %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message"
}

check_last_command() {
    local ret=$?
    local desc="$1"
    if [ $ret -eq 0 ]; then
        log "INFO" "✓ $desc completed successfully"
        return 0
    else
        log "ERROR" "✗ $desc failed (exit code: $ret)"
        return 1
    fi
}

is_package_installed() {
    opkg list-installed 2>/dev/null | grep -q "^$1 "
}

safe_backup() {
    local file="$1"
    [ -f "$file" ] && [ ! -f "${file}.bak" ] && cp "$file" "${file}.bak"
}

safe_uci_set() {
    uci set "$1"="$2" 2>/dev/null
    return $?
}

safe_uci_delete() {
    uci -q delete "$1" 2>/dev/null
    return 0
}

safe_uci_add_list() {
    uci add_list "$1"="$2" 2>/dev/null
    return $?
}

uci_commit_with_check() {
    local config="$1"
    uci commit "$config" 2>/dev/null
    check_last_command "UCI commit $config"
}

service_restart() {
    local service="$1"
    if [ -f "/etc/init.d/$service" ]; then
        /etc/init.d/"$service" restart >/dev/null 2>&1
        check_last_command "Restart $service"
    fi
}

# ============================================================================
# SYSTEM INFORMATION
# ============================================================================

print_system_info() {
    log "STEP" "========================================"
    log "STEP" "System Information"
    log "STEP" "========================================"
    
    log "INFO" "Script Version: v${SCRIPT_VERSION}"
    log "INFO" "Date: $(date '+%A, %d %B %Y %H:%M:%S')"
    
    if command -v ubus >/dev/null 2>&1; then
        local board_info=$(ubus call system board 2>/dev/null)
        if [ -n "$board_info" ]; then
            log "INFO" "System: $(echo "$board_info" | jsonfilter -e '$.system' 2>/dev/null || echo 'Unknown')"
            log "INFO" "Model: $(echo "$board_info" | jsonfilter -e '$.model' 2>/dev/null || echo 'Unknown')"
            log "INFO" "Board: $(echo "$board_info" | jsonfilter -e '$.board_name' 2>/dev/null || echo 'Unknown')"
        fi
    fi
    
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local disk_total=$(df -h / | awk 'NR==2{print $2}')
    local disk_avail=$(df / | awk 'NR==2{print $4}')
    
    log "INFO" "Memory: ${mem_total} MB"
    log "INFO" "Storage: ${disk_total}"
    
    # Warnings
    [ "$mem_total" -lt 128 ] && log "WARN" "Low memory detected (< 128MB)"
    [ "$disk_avail" -lt 5000 ] && log "WARN" "Low storage space (< 5MB available)"
    
    log "STEP" "========================================"
}

# ============================================================================
# FIRMWARE CUSTOMIZATION
# ============================================================================

customize_firmware() {
    log "STEP" "Customizing firmware branding"
    
    # System info customization
    local system_js="/www/luci-static/resources/view/status/include/10_system.js"
    if [ -f "$system_js" ]; then
        safe_backup "$system_js"
        sed -i "s#_('Firmware Version').*#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' [ RTA-WRT Build ]':''),#g" "$system_js"
        check_last_command "Update firmware description"
    else
        log "WARN" "System JS file not found: $system_js"
    fi
    
    # Ports customization
    local ports_js="/www/luci-static/resources/view/status/include/29_ports.js"
    if [ -f "$ports_js" ]; then
        safe_backup "$ports_js"
        sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" "$ports_js"
        check_last_command "Update port icons"
    fi
    
    # Distribution specific customization
    if grep -q "ImmortalWrt" /etc/openwrt_release 2>/dev/null; then
        log "INFO" "ImmortalWrt distribution detected"
        sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
        
        # Fix TTYD paths
        for header in "/usr/share/ucode/luci/template/themes/material/header.ut" \
                      "/usr/lib/lua/luci/view/themes/argon/header.htm"; do
            if [ -f "$header" ]; then
                safe_backup "$header"
                sed -i -E "s|services/ttyd|system/ttyd|g" "$header"
                log "DEBUG" "Updated TTYD path in $(basename "$header")"
            fi
        done
    elif grep -q "OpenWrt" /etc/openwrt_release 2>/dev/null; then
        log "INFO" "OpenWrt distribution detected"
        sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
    else
        log "WARN" "Unknown distribution variant"
    fi
}

# ============================================================================
# SECURITY
# ============================================================================

setup_root_password() {
    log "STEP" "Setting root password"
    
    (echo "$ROOT_PASSWORD"; sleep 1; echo "$ROOT_PASSWORD") | passwd root >/dev/null 2>&1
    check_last_command "Set root password"
}

# ============================================================================
# TIMEZONE & NTP
# ============================================================================

setup_timezone() {
    log "STEP" "Configuring timezone and NTP"
    
    safe_uci_set "system.@system[0].hostname" "$HOSTNAME"
    safe_uci_set "system.@system[0].timezone" "$TIMEZONE"
    safe_uci_set "system.@system[0].zonename" "$ZONENAME"
    
    # Clear existing NTP servers
    safe_uci_delete "system.ntp.server"
    
    # Add NTP servers
    local ntp_servers="0.pool.ntp.org 1.pool.ntp.org id.pool.ntp.org time.google.com time.cloudflare.com"
    for server in $ntp_servers; do
        safe_uci_add_list "system.ntp.server" "$server"
    done
    
    uci_commit_with_check "system"
    
    # Setup time sync cron job
    if [ -f "/sbin/sync_time.sh" ]; then
        chmod +x /sbin/sync_time.sh
        if ! grep -q "sync_time.sh" /etc/crontabs/root 2>/dev/null; then
            mkdir -p /etc/crontabs
            echo "0 */6 * * * /sbin/sync_time.sh >/dev/null 2>&1" >> /etc/crontabs/root
            service_restart "cron"
            log "INFO" "Added time sync to cron (every 6 hours)"
        fi
    fi
}

# ============================================================================
# NETWORK CONFIGURATION
# ============================================================================

setup_network() {
    log "STEP" "Configuring network interfaces"
    
    safe_backup "/etc/config/network"
    
    # LAN configuration
    safe_uci_set "network.lan.ipaddr" "$LAN_IP"
    safe_uci_set "network.lan.netmask" "$LAN_NETMASK"
    safe_uci_set "network.lan.dns" "8.8.8.8 1.1.1.1"
    
    # WAN configuration (ModemManager)
    safe_uci_set "network.wan" "interface"
    safe_uci_set "network.wan.proto" "modemmanager"
    safe_uci_set "network.wan.apn" "internet"
    safe_uci_set "network.wan.auth" "none"
    safe_uci_set "network.wan.iptype" "ipv4"
    
    # Auto-detect USB modem device
    local modem_device=""
    
    # Check for specific Raspberry Pi USB path
    if [ -d "/sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-1" ]; then
        modem_device="/sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-1"
        log "INFO" "Using Raspberry Pi USB modem path"
    else
        # Try to auto-detect wwan interface
        modem_device=$(ls -d /sys/class/net/wwan* 2>/dev/null | head -1)
        if [ -n "$modem_device" ]; then
            log "INFO" "Auto-detected USB modem: $modem_device"
        else
            modem_device="/sys/devices/platform/*/usb*/*/usb*"
            log "WARN" "No USB modem detected, using wildcard path"
        fi
    fi
    
    safe_uci_set "network.wan.device" "$modem_device"
    
    # Failover WAN (eth1)
    if [ -e "/sys/class/net/eth1" ]; then
        log "INFO" "Configuring failover WAN on eth1"
        safe_uci_set "network.wan2" "interface"
        safe_uci_set "network.wan2.proto" "dhcp"
        safe_uci_set "network.wan2.device" "eth1"
        safe_uci_set "firewall.@zone[1].network" "wan wan2"
        uci_commit_with_check "firewall"
    fi
    
    uci_commit_with_check "network"
}

# ============================================================================
# DISABLE IPv6
# ============================================================================

disable_ipv6() {
    log "STEP" "Disabling IPv6"
    
    safe_uci_delete "dhcp.lan.dhcpv6"
    safe_uci_delete "dhcp.lan.ra"
    safe_uci_delete "dhcp.lan.ndp"
    uci_commit_with_check "dhcp"
    
    # System-wide IPv6 disable
    if [ -f "/etc/sysctl.conf" ]; then
        if ! grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf; then
            cat >> /etc/sysctl.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
            sysctl -p >/dev/null 2>&1
            log "INFO" "IPv6 disabled system-wide"
        fi
    fi
}

# ============================================================================
# WIRELESS CONFIGURATION
# ============================================================================

setup_wireless() {
    log "STEP" "Configuring wireless"
    
    # Generate wireless config if not exists
    if [ ! -f "/etc/config/wireless" ]; then
        wifi detect > /etc/config/wireless 2>/dev/null
        check_last_command "WiFi detection"
    fi
    
    safe_backup "/etc/config/wireless"
    
    # Check if wireless devices exist
    if ! grep -q "wifi-device" /etc/config/wireless 2>/dev/null; then
        log "WARN" "No wireless devices found"
        return 1
    fi
    
    # Basic wireless configuration
    safe_uci_set "wireless.@wifi-device[0].disabled" "0"
    safe_uci_set "wireless.@wifi-iface[0].disabled" "0"
    safe_uci_set "wireless.@wifi-iface[0].encryption" "none"
    safe_uci_set "wireless.@wifi-device[0].country" "ID"
    
    # Detect device type for optimal settings
    local is_rpi=0
    if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo 2>/dev/null; then
        is_rpi=1
        log "INFO" "Raspberry Pi detected - configuring for 5GHz"
        safe_uci_set "wireless.@wifi-iface[0].ssid" "$WIFI_5G_SSID"
        safe_uci_set "wireless.@wifi-device[0].channel" "149"
        safe_uci_set "wireless.@wifi-device[0].htmode" "HT40"
        safe_uci_set "wireless.@wifi-device[0].band" "5g"
    else
        log "INFO" "Standard device - configuring for 2.4GHz"
        safe_uci_set "wireless.@wifi-iface[0].ssid" "$WIFI_2G_SSID"
        safe_uci_set "wireless.@wifi-device[0].channel" "1"
        safe_uci_set "wireless.@wifi-device[0].band" "2g"
    fi
    
    uci_commit_with_check "wireless"
    
    # Restart wireless
    wifi reload 2>/dev/null || { wifi down; sleep 2; wifi up; }
    
    # Verify wireless is up
    if iw dev 2>/dev/null | grep -q "Interface"; then
        log "INFO" "Wireless interface configured successfully"
        
        # Raspberry Pi specific fixes
        if [ "$is_rpi" -eq 1 ]; then
            # Add WiFi restart to rc.local
            if [ -f "/etc/rc.local" ]; then
                safe_backup "/etc/rc.local"
                if ! grep -q "wifi up" /etc/rc.local; then
                    sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local
                    log "INFO" "Added WiFi startup to rc.local"
                fi
            fi
            
            # Add WiFi restart to cron
            if ! grep -q "wifi up" /etc/crontabs/root 2>/dev/null; then
                mkdir -p /etc/crontabs
                echo "0 */12 * * * wifi down && sleep 5 && wifi up" >> /etc/crontabs/root
                service_restart "cron"
                log "INFO" "Added WiFi restart to cron (every 12 hours)"
            fi
        fi
    else
        log "WARN" "No wireless interface detected after configuration"
    fi
}

# ============================================================================
# PACKAGE MANAGEMENT
# ============================================================================

setup_package_management() {
    log "STEP" "Configuring package management"
    
    # Disable signature checking
    if [ -f "/etc/opkg.conf" ]; then
        safe_backup "/etc/opkg.conf"
        sed -i 's/^option check_signature/#&/g' /etc/opkg.conf
    fi
    
    # Add custom repository
    mkdir -p /etc/opkg
    touch /etc/opkg/customfeeds.conf
    
    # Detect architecture
    local arch=""
    if [ -f "/etc/os-release" ]; then
        arch=$(grep "OPENWRT_ARCH" /etc/os-release 2>/dev/null | awk -F '"' '{print $2}')
    fi
    
    if [ -z "$arch" ]; then
        arch=$(opkg list-installed | grep "base-files" | awk '{print $3}' | cut -d'_' -f1)
    fi
    
    if [ -n "$arch" ]; then
        if ! grep -q "custom_packages" /etc/opkg/customfeeds.conf 2>/dev/null; then
            echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/${arch}/kiddin9" >> /etc/opkg/customfeeds.conf
            log "INFO" "Added custom repository for architecture: $arch"
        fi
    else
        log "WARN" "Could not determine system architecture"
    fi
}

# ============================================================================
# UI CONFIGURATION
# ============================================================================

setup_ui() {
    log "STEP" "Configuring UI"
    
    # Set Material theme if available
    if [ -d "/www/luci-static/material" ]; then
        safe_uci_set "luci.main.mediaurlbase" "/luci-static/material"
        uci_commit_with_check "luci"
        log "INFO" "Material theme enabled"
    fi
    
    # Configure TTYD
    if is_package_installed "ttyd"; then
        if ! uci show ttyd >/dev/null 2>&1; then
            touch /etc/config/ttyd
            uci add ttyd ttyd >/dev/null 2>&1
        fi
        
        safe_uci_set "ttyd.@ttyd[0].command" "/bin/bash --login"
        safe_uci_set "ttyd.@ttyd[0].interface" "@lan"
        safe_uci_set "ttyd.@ttyd[0].port" "7681"
        uci_commit_with_check "ttyd"
        service_restart "ttyd"
    fi
}

# ============================================================================
# USB MODEM CONFIGURATION
# ============================================================================

setup_usb_modem() {
    log "STEP" "Configuring USB modem"
    
    # Update USB mode switch database
    if [ -f "/etc/usb-mode.json" ]; then
        safe_backup "/etc/usb-mode.json"
        
        # Remove problematic USB IDs
        local problematic_ids="12d1:15c1 413c:81d7 1e2d:00b3"
        for vid_pid in $problematic_ids; do
            if grep -q "$vid_pid" /etc/usb-mode.json; then
                sed -i -e "/$vid_pid/,+5d" /etc/usb-mode.json
                log "DEBUG" "Removed USB ID: $vid_pid"
            fi
        done
    fi
    
    # Disable XMM modem if exists
    if [ -f "/etc/config/xmm-modem" ]; then
        safe_uci_set "xmm-modem.@xmm-modem[0].enable" "0"
        uci_commit_with_check "xmm-modem"
        [ -f "/etc/init.d/xmm-modem" ] && /etc/init.d/xmm-modem stop >/dev/null 2>&1
    fi
    
    # Load required kernel modules
    for module in option qmi_wwan; do
        if ! lsmod | grep -q "$module"; then
            modprobe "$module" 2>/dev/null && log "DEBUG" "Loaded module: $module"
        fi
    done
}

# ============================================================================
# TRAFFIC MONITORING
# ============================================================================

setup_traffic_monitoring() {
    log "STEP" "Configuring traffic monitoring"
    
    # Configure nlbwmon
    if is_package_installed "nlbwmon"; then
        mkdir -p /etc/nlbwmon
        
        if ! uci show nlbwmon >/dev/null 2>&1; then
            touch /etc/config/nlbwmon
            uci add nlbwmon nlbwmon >/dev/null 2>&1
        fi
        
        safe_uci_set "nlbwmon.@nlbwmon[0].database_directory" "/etc/nlbwmon"
        safe_uci_set "nlbwmon.@nlbwmon[0].commit_interval" "3h"
        safe_uci_set "nlbwmon.@nlbwmon[0].refresh_interval" "30s"
        safe_uci_set "nlbwmon.@nlbwmon[0].database_limit" "10000"
        uci_commit_with_check "nlbwmon"
        service_restart "nlbwmon"
    fi
    
    # Configure vnstat
    if is_package_installed "vnstat"; then
        mkdir -p /etc/vnstat
        chmod 755 /etc/vnstat
        
        if [ -f "/etc/vnstat.conf" ]; then
            safe_backup "/etc/vnstat.conf"
            sed -i 's|;DatabaseDir.*|DatabaseDir "/etc/vnstat"|' /etc/vnstat.conf
        fi
        
        service_restart "vnstat"
        
        # Enable vnstat backup if available
        if [ -f "/etc/init.d/vnstat_backup" ]; then
            chmod +x /etc/init.d/vnstat_backup
            /etc/init.d/vnstat_backup enable >/dev/null 2>&1
        fi
        
        # Run vnstati if available
        if [ -f "/www/vnstati/vnstati.sh" ]; then
            chmod +x /www/vnstati/vnstati.sh
            /www/vnstati/vnstati.sh >/dev/null 2>&1 &
        fi
    fi
}

# ============================================================================
# APPLICATION CATEGORIES
# ============================================================================

adjust_app_categories() {
    log "STEP" "Adjusting application categories"
    
    local menu_dir="/usr/share/luci/menu.d"
    
    # Move lite-watchdog to modem category
    if [ -f "$menu_dir/luci-app-lite-watchdog.json" ]; then
        safe_backup "$menu_dir/luci-app-lite-watchdog.json"
        sed -i 's/"services"/"modem"/g' "$menu_dir/luci-app-lite-watchdog.json"
    fi
    
    # Move modem-related apps to modem category
    for app in luci-app-modeminfo luci-app-sms-tool luci-app-mmconfig; do
        if [ -f "$menu_dir/$app.json" ]; then
            safe_backup "$menu_dir/$app.json"
            sed -i 's/"services"/"modem"/g' "$menu_dir/$app.json"
        fi
    done
}

# ============================================================================
# SHELL ENVIRONMENT
# ============================================================================

setup_shell_environment() {
    log "STEP" "Configuring shell environment"
    
    # Disable banner in profile
    if [ -f "/etc/profile" ]; then
        safe_backup "/etc/profile"
        sed -i 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' /etc/profile
        sed -i 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/#&/' /etc/profile
    fi
    
    # Make scripts executable
    local scripts="/sbin/sync_time.sh /sbin/free.sh /usr/bin/clock /usr/bin/openclash.sh /usr/bin/cek_sms.sh"
    for script in $scripts; do
        [ -f "$script" ] && chmod +x "$script" && log "DEBUG" "Made executable: $script"
    done
}

# ============================================================================
# TUNNEL APPLICATIONS
# ============================================================================

check_tunnel_apps() {
    log "STEP" "Checking tunnel applications"
    
    local installed_apps=""
    for app in luci-app-openclash luci-app-nikki luci-app-passwall; do
        if is_package_installed "$app"; then
            installed_apps="${installed_apps}$app "
        fi
    done
    
    if [ -n "$installed_apps" ]; then
        log "INFO" "Installed tunnel apps: $installed_apps"
    else
        log "INFO" "No tunnel applications installed"
    fi
}

configure_openclash() {
    log "STEP" "Configuring OpenClash"
    
    if is_package_installed "luci-app-openclash"; then
        mkdir -p /etc/openclash/core /etc/openclash/history
        chmod 755 /etc/openclash
        
        # Set executable permissions for core files
        for file in /etc/openclash/core/clash_meta \
                    /etc/openclash/GeoIP.dat \
                    /etc/openclash/GeoSite.dat \
                    /etc/openclash/Country.mmdb; do
            [ -f "$file" ] && chmod +x "$file"
        done
        
        # Apply OpenClash patch
        if [ -f "/usr/bin/patchoc.sh" ]; then
            chmod +x /usr/bin/patchoc.sh
            /usr/bin/patchoc.sh
            
            if [ -f "/etc/rc.local" ] && ! grep -q "patchoc.sh" /etc/rc.local; then
                sed -i '/exit 0/i /usr/bin/patchoc.sh' /etc/rc.local
            fi
        fi
        
        # Create symlinks
        ln -sf /etc/openclash/history/config-wrt.db /etc/openclash/cache.db 2>/dev/null
        ln -sf /etc/openclash/core/clash_meta /etc/openclash/clash 2>/dev/null
        
        # Restore config if backup exists
        if [ -f "/etc/config/openclash1" ]; then
            safe_backup "/etc/config/openclash"
            mv /etc/config/openclash1 /etc/config/openclash
        fi
        
        # Restart if not running
        if ! pgrep -f clash >/dev/null; then
            service_restart "openclash"
        fi
    else
        # Cleanup if not installed
        rm -rf /etc/config/openclash1
        if [ -f "/etc/config/internet-detector" ]; then
            safe_uci_delete "internet-detector.Openclash"
            uci_commit_with_check "internet-detector"
            service_restart "internet-detector"
        fi
    fi
}

configure_nikki() {
    log "STEP" "Configuring Nikki"
    
    if is_package_installed "luci-app-nikki"; then
        mkdir -p /etc/nikki/run
        chmod 755 /etc/nikki
        
        for file in /etc/nikki/run/GeoIP.dat /etc/nikki/run/GeoSite.dat; do
            [ -f "$file" ] && chmod +x "$file"
        done
        
        if ! pgrep -f nikki >/dev/null; then
            service_restart "nikki"
        fi
    else
        rm -rf /etc/config/nikki /etc/nikki
    fi
}

# ============================================================================
# PHP & WEB SERVICES
# ============================================================================

setup_php() {
    log "STEP" "Configuring PHP"
    
    if is_package_installed "php8" || is_package_installed "php7"; then
        safe_uci_set "uhttpd.main.ubus_prefix" "/ubus"
        safe_uci_set "uhttpd.main.interpreter" ".php=/usr/bin/php-cgi"
        safe_uci_set "uhttpd.main.index_page" "cgi-bin/luci"
        safe_uci_add_list "uhttpd.main.index_page" "index.html"
        safe_uci_add_list "uhttpd.main.index_page" "index.php"
        uci_commit_with_check "uhttpd"
        
        # Configure PHP settings
        if [ -f "/etc/php.ini" ]; then
            safe_backup "/etc/php.ini"
            sed -i -E "s|memory_limit = [0-9]+M|memory_limit = 128M|g" /etc/php.ini
            sed -i -E "s|max_execution_time = [0-9]+|max_execution_time = 60|g" /etc/php.ini
            sed -i -E "s|display_errors = On|display_errors = Off|g" /etc/php.ini
            sed -i -E "s|;date.timezone =|date.timezone = Asia/Jakarta|g" /etc/php.ini
        fi
        
        # Create symlinks
        ln -sf /usr/bin/php-cli /usr/bin/php 2>/dev/null
        [ -d "/usr/lib/php8" ] && [ ! -d "/usr/lib/php" ] && ln -sf /usr/lib/php8 /usr/lib/php
        
        service_restart "uhttpd"
    fi
}

setup_tinyfm() {
    log "STEP" "Configuring TinyFM"
    
    mkdir -p /www/tinyfm
    ln -sf / /www/tinyfm/rootfs 2>/dev/null
    chmod 755 /www/tinyfm
    log "INFO" "TinyFM directory configured"
}

# ============================================================================
# SYSTEM RESTORE
# ============================================================================

restore_sysinfo() {
    log "STEP" "Restoring system info"
    
    if [ -f "/etc/profile.d/30-sysinfo.sh-bak" ]; then
        mv /etc/profile.d/30-sysinfo.sh-bak /etc/profile.d/30-sysinfo.sh
        chmod +x /etc/profile.d/30-sysinfo.sh
        log "INFO" "System info restored"
    fi
}

# ============================================================================
# SECONDARY INSTALL
# ============================================================================

setup_secondary_install() {
    log "STEP" "Running secondary install"
    
    if [ -f "/root/install2.sh" ]; then
        chmod +x /root/install2.sh
        log "INFO" "Executing install2.sh..."
        /root/install2.sh >> "$LOGFILE" 2>&1
        check_last_command "Secondary install script"
    else
        log "INFO" "No secondary install script found"
    fi
}

# ============================================================================
# FINALIZATION
# ============================================================================

generate_summary() {
    log "STEP" "========================================"
    log "STEP" "Setup Summary"
    log "STEP" "========================================"
    log "INFO" "Hostname: $HOSTNAME"
    log "INFO" "LAN IP: $LAN_IP"
    log "INFO" "Netmask: $LAN_NETMASK"
    log "INFO" "Timezone: $ZONENAME"
    log "INFO" "Root Password: $ROOT_PASSWORD"
    log "INFO" "WiFi 2.4GHz SSID: $WIFI_2G_SSID"
    log "INFO" "WiFi 5GHz SSID: $WIFI_5G_SSID"
    log "STEP" "========================================"
}

save_final_state() {
    log "INFO" "Saving final system state..."
    
    {
        echo "=== Final System State ==="
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "=== System Info ==="
        uptime
        echo ""
        echo "=== Memory ==="
        free -h
        echo ""
        echo "=== Disk Usage ==="
        df -h
        echo ""
        echo "=== Network Interfaces ==="
        ifconfig | grep -E "^[a-z]|inet "
        echo ""
        echo "=== Enabled Services ==="
        ls /etc/rc.d/S* 2>/dev/null | cut -d/ -f4 | sort
        echo ""
        echo "=== UCI Network Config ==="
        uci show network 2>/dev/null | grep -v "\.password="
        echo ""
        echo "=== UCI Wireless Config ==="
        uci show wireless 2>/dev/null | grep -v "\.key="
    } >> "$LOGFILE"
}

cleanup() {
    log "STEP" "Performing cleanup"
    
    # Remove temporary files
    rm -rf /tmp/* 2>/dev/null
    rm -f /root/install2.sh 2>/dev/null
    
    # Remove UCI defaults script
    rm -f /etc/uci-defaults/$(basename "$0") 2>/dev/null
    
    # Copy final log
    cp "$LOGFILE" "/root/setup_complete_$(date +%Y%m%d_%H%M%S).log"
    
    log "INFO" "Cleanup completed"
}

complete_setup() {
    generate_summary
    save_final_state
    cleanup
    
    log "STEP" "========================================"
    log "STEP" "Setup completed successfully!"
    log "STEP" "========================================"
    log "INFO" "Log file saved to: $LOGFILE"
    log "WARN" "System will reboot in 10 seconds..."
    log "INFO" "After reboot, access router at: http://$LAN_IP"
    
    sync
    sleep 10
    reboot
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

handle_error() {
    local exit_code=$?
    local line_number=$1
    
    log "ERROR" "Script failed at line $line_number with exit code $exit_code"
    log "ERROR" "Check log file for details: $LOGFILE"
    
    # Don't reboot on error, allow manual inspection
    exit $exit_code
}

trap 'handle_error ${LINENO}' ERR

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log "STEP" "========================================"
    log "STEP" "RTA-WRT Router Setup v${SCRIPT_VERSION}"
    log "STEP" "========================================"
    log "INFO" "Starting automated router configuration..."
    log "INFO" "Log file: $LOGFILE"
    log "STEP" "========================================"
    
    # Execute setup steps
    print_system_info
    customize_firmware
    check_tunnel_apps
    setup_root_password
    setup_timezone
    setup_network
    disable_ipv6
    setup_wireless
    setup_package_management
    setup_ui
    setup_usb_modem
    setup_traffic_monitoring
    adjust_app_categories
    setup_shell_environment
    configure_openclash
    configure_nikki
    setup_php
    setup_tinyfm
    restore_sysinfo
    setup_secondary_install
    complete_setup
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Execute main function
main "$@"