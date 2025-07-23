#!/bin/sh


# Initialize logging
LOGFILE="/root/setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
  local color="$NC"
  case "$1" in
    "INFO") color="$GREEN" ;;
    "WARNING") color="$YELLOW" ;;
    "ERROR") color="$RED" ;;
    "STEP") color="$BLUE" ;;
  esac
  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2${NC}"
}

# Check command success
check_command() {
  [ $? -eq 0 ] && log "INFO" "✓ $1 completed" || { log "ERROR" "✗ $1 failed"; return 1; }
}

# Check if package is installed
is_package_installed() {
  opkg list-installed | grep -q "^$1 "
}

# Safe UCI configuration
safe_uci() {
  case "$1" in
    set) uci set "$2"="$3" ;;
    add_list) uci add_list "$2"="$3" ;;
    delete) uci -q delete "$2" ;;
    *) log "ERROR" "Unknown UCI command: $1"; return 1 ;;
  esac
  check_command "UCI $1 $2"
}

# Commit UCI changes
commit_uci() {
  uci commit "$1"
  check_command "Commit UCI $1"
}

# Print system information
print_system_info() {
  log "STEP" "System Information"
  log "INFO" "Date: $(date '+%A, %d %B %Y %T')"
  log "INFO" "Processor: $(ubus call system board | jsonfilter -e '$.system')"
  log "INFO" "Model: $(ubus call system board | jsonfilter -e '$.model')"
  log "INFO" "Board: $(ubus call system board | jsonfilter -e '$.board_name')"
  log "INFO" "Memory: $(free -m | grep Mem | awk '{print $2}') MB"
  log "INFO" "Storage: $(df -h / | tail -1 | awk '{print $2}')"
  [ "$(free -m | grep Mem | awk '{print $2}')" -lt 128 ] && log "WARNING" "Low memory detected"
  [ "$(df / | tail -1 | awk '{print $4}')" -lt 5000 ] && log "WARNING" "Low storage detected"
}

# Customize firmware
customize_firmware() {
  log "STEP" "Customizing firmware"
  local JS_FILE="/www/luci-static/resources/view/status/include/10_system.js"
  local PORTS_FILE="/www/luci-static/resources/view/status/include/29_ports.js"

  [ -f "$JS_FILE" ] && {
    cp "$JS_FILE" "${JS_FILE}.bak"
    sed -i "s#_('Firmware Version').*#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' build by RTA-WRT [ Ouc3kNF6 ]':''),#g" "$JS_FILE"
    check_command "Firmware description"
  } || log "WARNING" "System JS file not found"

  [ -f "$PORTS_FILE" ] && {
    cp "$PORTS_FILE" "${PORTS_FILE}.bak"
    sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" "$PORTS_FILE"
    check_command "Ports icons"
  } || log "WARNING" "Ports JS file not found"

  if grep -q "ImmortalWrt" /etc/openwrt_release; then
    log "INFO" "ImmortalWrt detected"
    sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
    for f in "/usr/share/ucode/luci/template/themes/material/header.ut" "/usr/lib/lua/luci/view/themes/argon/header.htm"; do
      [ -f "$f" ] && {
        cp "$f" "${f}.bak"
        sed -i -E "s|services/ttyd|system/ttyd|g" "$f"
        check_command "TTYD path in $(basename "$f")"
      }
    done
  elif grep -q "OpenWrt" /etc/openwrt_release; then
    log "INFO" "OpenWrt detected"
    sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  else
    log "WARNING" "Unknown OpenWrt variant"
  fi
}

# Check tunnel applications
check_tunnel_apps() {
  log "STEP" "Checking tunnel applications"
  local apps=""
  for app in luci-app-openclash luci-app-nikki luci-app-passwall; do
    is_package_installed "$app" && apps="$apps$app "
  done
  [ -n "$apps" ] && log "INFO" "Installed: $apps" || log "INFO" "No tunnel applications installed"
}

# Set root password
setup_root_password() {
  log "STEP" "Setting root password"
  (echo "rtawrt"; sleep 1; echo "rtawrt") | passwd root > /dev/null
  check_command "Root password"
}

# Configure timezone and NTP
setup_timezone() {
  log "STEP" "Configuring timezone and NTP"
  safe_uci set "system.@system[0].hostname" "RTA-WRT"
  safe_uci set "system.@system[0].timezone" "WIB-7"
  safe_uci set "system.@system[0].zonename" "Asia/Jakarta"
  safe_uci delete "system.ntp.server"
  for s in "0.pool.ntp.org" "1.pool.ntp.org" "id.pool.ntp.org" "time.google.com" "time.cloudflare.com"; do
    safe_uci add_list "system.ntp.server" "$s"
  done
  commit_uci "system"
  [ -f "/sbin/sync_time.sh" ] && ! grep -q "sync_time.sh" /etc/crontabs/root && {
    mkdir -p /etc/crontabs
    echo "0 */6 * * * /sbin/sync_time.sh >/dev/null 2>&1" >> /etc/crontabs/root
    /etc/init.d/cron restart
    log "INFO" "Added time sync to cron"
  }
}

# Configure network
setup_network() {
  log "STEP" "Configuring network"
  cp /etc/config/network /etc/config/network.bak
  safe_uci set "network.lan.ipaddr" "192.168.1.1"
  safe_uci set "network.lan.netmask" "255.255.255.0"
  safe_uci set "network.lan.dns" "8.8.8.8,1.1.1.1"
  safe_uci set "network.wan" "interface"
  safe_uci set "network.wan.proto" "modemmanager"

  if [ -d "/sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-1" ]; then
    safe_uci set "network.wan.device" "/sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-1"
  else
    local modem=$(ls -d /sys/class/net/wwan* 2>/dev/null | head -1)
    [ -n "$modem" ] && {
      safe_uci set "network.wan.device" "$modem"
      log "INFO" "Auto-detected USB modem: $modem"
    } || {
      safe_uci set "network.wan.device" "/sys/devices/platform/*/usb*/*/usb*"
      log "WARNING" "No USB modem detected"
    }
  fi
  safe_uci set "network.wan.apn" "internet"
  safe_uci set "network.wan.auth" "none"
  safe_uci set "network.wan.iptype" "ipv4"
  [ -e "/sys/class/net/eth1" ] && {
    log "INFO" "Configuring failover WAN"
    safe_uci set "network.wan2" "interface"
    safe_uci set "network.wan2.proto" "dhcp"
    safe_uci set "network.wan2.device" "eth1"
    safe_uci set "firewall.@zone[1].network" "wan wan2"
    commit_uci "firewall"
  }
  commit_uci "network"
}

# Disable IPv6
disable_ipv6() {
  log "STEP" "Disabling IPv6"
  safe_uci delete "dhcp.lan.dhcpv6"
  safe_uci delete "dhcp.lan.ra"
  safe_uci delete "dhcp.lan.ndp"
  commit_uci "dhcp"
  [ -f "/etc/sysctl.conf" ] && ! grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf && {
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    log "INFO" "IPv6 disabled"
  }
}

# Configure wireless
setup_wireless() {
  log "STEP" "Configuring wireless"
  [ ! -f /etc/config/wireless ] && {
    wifi detect > /etc/config/wireless
    check_command "WiFi detect"
  }
  [ -f /etc/config/wireless ] && cp /etc/config/wireless /etc/config/wireless.bak
  grep -q "wifi-device" /etc/config/wireless || { log "WARNING" "No wireless devices found"; return 1; }
  safe_uci set "wireless.@wifi-device[0].disabled" "0"
  safe_uci set "wireless.@wifi-iface[0].disabled" "0"
  safe_uci set "wireless.@wifi-iface[0].encryption" "none"
  safe_uci set "wireless.@wifi-device[0].country" "ID"
  if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo 2>/dev/null; then
    safe_uci set "wireless.@wifi-iface[0].ssid" "RTA-WRT_5G"
    safe_uci set "wireless.@wifi-device[0].channel" "149"
    safe_uci set "wireless.@wifi-device[0].htmode" "HT40"
    safe_uci set "wireless.@wifi-device[0].band" "5g"
  else
    safe_uci set "wireless.@wifi-iface[0].ssid" "RTA-WRT_2G"
    safe_uci set "wireless.@wifi-device[0].channel" "1"
    safe_uci set "wireless.@wifi-device[0].band" "2g"
  fi
  commit_uci "wireless"
  wifi reload || { wifi down; sleep 2; wifi up; }
  iw dev | grep -q Interface && {
    log "INFO" "Wireless configured"
    if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo 2>/dev/null; then
      [ -f "/etc/rc.local" ] && ! grep -q "wifi up" /etc/rc.local && {
        cp /etc/rc.local /etc/rc.local.bak
        sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local
        log "INFO" "Added wireless restart to rc.local"
      }
      ! grep -q "wifi up" /etc/crontabs/root 2>/dev/null && {
        mkdir -p /etc/crontabs
        echo "0 */12 * * * wifi down && sleep 5 && wifi up" >> /etc/crontabs/root
        /etc/init.d/cron restart
        log "INFO" "Added wireless restart to cron"
      }
    }
  } || log "WARNING" "No wireless interface detected"
}

# Configure package management
setup_package_management() {
  log "STEP" "Configuring package management"
  [ -f "/etc/opkg.conf" ] && {
    cp /etc/opkg.conf /etc/opkg.conf.bak
    sed -i 's/option check_signature/#&/g' /etc/opkg.conf
  }
  mkdir -p /etc/opkg
  touch /etc/opkg/customfeeds.conf
  local arch=$(grep "OPENWRT_ARCH" /etc/os-release 2>/dev/null | awk -F '"' '{print $2}' || opkg list-installed | grep base-files | awk '{print $3}' | cut -d '_' -f 1)
  [ -n "$arch" ] && ! grep -q "custom_packages" /etc/opkg/customfeeds.conf && {
    echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/${arch}/kiddin9" >> /etc/opkg/customfeeds.conf
    log "INFO" "Added custom repository for $arch"
  } || log "WARNING" "Could not determine architecture"
}

# Configure UI
setup_ui() {
  log "STEP" "Configuring UI"
  [ -d "/www/luci-static/material" ] && {
    safe_uci set "luci.main.mediaurlbase" "/luci-static/material"
    commit_uci "luci"
    log "INFO" "Set MATERIAL theme"
  }
  is_package_installed "ttyd" && {
    uci show ttyd >/dev/null 2>&1 || {
      touch /etc/config/ttyd
      uci set ttyd.@ttyd[-1]=ttyd
    }
    safe_uci set "ttyd.@ttyd[0].command" "/bin/bash --login"
    safe_uci set "ttyd.@ttyd[0].interface" "@lan"
    safe_uci set "ttyd.@ttyd[0].port" "7681"
    commit_uci "ttyd"
    [ -f "/etc/init.d/ttyd" ] && /etc/init.d/ttyd restart && log "INFO" "TTYD configured"
  }
}

# Configure USB modem
setup_usb_modem() {
  log "STEP" "Configuring USB modem"
  [ -f "/etc/usb-mode.json" ] && {
    cp /etc/usb-mode.json /etc/usb-mode.json.bak
    for vid_pid in "12d1:15c1" "413c:81d7" "1e2d:00b3"; do
      grep -q "$vid_pid" /etc/usb-mode.json && sed -i -e "/$vid_pid/,+5d" /etc/usb-mode.json
    done
    log "INFO" "USB mode switch updated"
  }
  [ -f "/etc/config/xmm-modem" ] && {
    safe_uci set "xmm-modem.@xmm-modem[0].enable" "0"
    commit_uci "xmm-modem"
    [ -f "/etc/init.d/xmm-modem" ] && /etc/init.d/xmm-modem stop
  }
  lsmod | grep -q "option" || modprobe option
  lsmod | grep -q "qmi_wwan" || modprobe qmi_wwan
}

# Configure traffic monitoring
setup_traffic_monitoring() {
  log "STEP" "Configuring traffic monitoring"
  is_package_installed "nlbwmon" && {
    mkdir -p /etc/nlbwmon
    uci show nlbwmon >/dev/null 2>&1 || {
      touch /etc/config/nlbwmon
      uci set nlbwmon.@nlbwmon[-1]=nlbwmon
    }
    safe_uci set "nlbwmon.@nlbwmon[0].database_directory" "/etc/nlbwmon"
    safe_uci set "nlbwmon.@nlbwmon[0].commit_interval" "3h"
    safe_uci set "nlbwmon.@nlbwmon[0].refresh_interval" "30s"
    safe_uci set "nlbwmon.@nlbwmon[0].database_limit" "10000"
    commit_uci "nlbwmon"
    [ -f "/etc/init.d/nlbwmon" ] && /etc/init.d/nlbwmon restart
  }
  is_package_installed "vnstat" && {
    mkdir -p /etc/vnstat
    chmod 755 /etc/vnstat
    [ -f "/etc/vnstat.conf" ] && {
      cp /etc/vnstat.conf /etc/vnstat.conf.bak
      sed -i 's|;DatabaseDir.*|DatabaseDir "/etc/vnstat"|' /etc/vnstat.conf
    }
    [ -f "/etc/init.d/vnstat" ] && /etc/init.d/vnstat enable && /etc/init.d/vnstat restart
    [ -f "/etc/init.d/vnstat_backup" ] && chmod +x /etc/init.d/vnstat_backup && /etc/init.d/vnstat_backup enable
    [ -f "/www/vnstati/vnstati.sh" ] && chmod +x /www/vnstati/vnstati.sh && /www/vnstati/vnstati.sh
  }
}

# Adjust application categories
adjust_app_categories() {
  log "STEP" "Adjusting app categories"
  local menu_dir="/usr/share/luci/menu.d"
  [ -f "$menu_dir/luci-app-lite-watchdog.json" ] && {
    cp "$menu_dir/luci-app-lite-watchdog.json" "$menu_dir/luci-app-lite-watchdog.json.bak"
    sed -i 's/services/modem/g' "$menu_dir/luci-app-lite-watchdog.json"
  }
  for app in luci-app-modeminfo luci-app-sms-tool luci-app-mmconfig; do
    [ -f "$menu_dir/$app.json" ] && {
      cp "$menu_dir/$app.json" "$menu_dir/$app.json.bak"
      sed -i 's/"services"/"modem"/g' "$menu_dir/$app.json"
    }
  done
}

# Configure shell environment
setup_shell_environment() {
  log "STEP" "Configuring shell environment"
  [ -f "/etc/profile" ] && {
    cp /etc/profile /etc/profile.bak
    sed -i 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' /etc/profile
    sed -i 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/#&/' /etc/profile
  }
  for script in /sbin/sync_time.sh /sbin/free.sh /usr/bin/clock /usr/bin/openclash.sh /usr/bin/cek_sms.sh; do
    [ -f "$script" ] && chmod +x "$script"
  done
}

# Configure OpenClash
configure_openclash() {
  log "STEP" "Configuring OpenClash"
  is_package_installed "luci-app-openclash" && {
    mkdir -p /etc/openclash/{core,history}
    chmod 755 /etc/openclash
    for f in /etc/openclash/core/clash_meta /etc/openclash/GeoIP.dat /etc/openclash/GeoSite.dat /etc/openclash/Country.mmdb; do
      [ -f "$f" ] && chmod +x "$f"
    done
    [ -f "/usr/bin/patchoc.sh" ] && {
      chmod +x /usr/bin/patchoc.sh
      /usr/bin/patchoc.sh
      ! grep -q "patchoc.sh" /etc/rc.local && {
        sed -i '/exit 0/i /usr/bin/patchoc.sh' /etc/rc.local
      }
    }
    ln -sf /etc/openclash/history/config-wrt.db /etc/openclash/cache.db 2>/dev/null
    ln -sf /etc/openclash/core/clash_meta /etc/openclash/clash 2>/dev/null
    [ -f "/etc/config/openclash1" ] && {
      [ -f "/etc/config/openclash" ] && cp /etc/config/openclash /etc/config/openclash.bak
      mv /etc/config/openclash1 /etc/config/openclash
    }
    pgrep -f clash >/dev/null || /etc/init.d/openclash restart
  } || {
    rm -rf /etc/config/openclash1
    [ -f "/etc/config/internet-detector" ] && {
      uci delete internet-detector.Openclash 2>/dev/null
      uci commit internet-detector
      service internet-detector restart
    }
  }
}

# Configure Nikki
configure_nikki() {
  log "STEP" "Configuring Nikki"
  is_package_installed "luci-app-nikki" && {
    mkdir -p /etc/nikki/run
    chmod 755 /etc/nikki
    for f in /etc/nikki/run/GeoIP.dat /etc/nikki/run/GeoSite.dat; do
      [ -f "$f" ] && chmod +x "$f"
    done
    pgrep -f nikki >/dev/null || /etc/init.d/nikki restart
  } || rm -rf /etc/config/nikki /etc/nikki
}

# Configure PHP
setup_php() {
  log "STEP" "Configuring PHP"
  if is_package_installed "php8" || is_package_installed "php7"; then
    safe_uci set "uhttpd.main.ubus_prefix" "/ubus"
    safe_uci set "uhttpd.main.interpreter" ".php=/usr/bin/php-cgi"
    safe_uci set "uhttpd.main.index_page" "cgi-bin/luci"
    safe_uci add_list "uhttpd.main.index_page" "index.html"
    safe_uci add_list "uhttpd.main.index_page" "index.php"
    commit_uci "uhttpd"
    [ -f "/etc/php.ini" ] && {
      cp /etc/php.ini /etc/php.ini.bak
      sed -i -E "s|memory_limit = [0-9]+M|memory_limit = 128M|g" /etc/php.ini
      sed -i -E "s|max_execution_time = [0-9]+|max_execution_time = 60|g" /etc/php.ini
      sed -i -E "s|display_errors = On|display_errors = Off|g" /etc/php.ini
      sed -i -E "s|;date.timezone =|date.timezone = Asia/Jakarta|g" /etc/php.ini
    }
    ln -sf /usr/bin/php-cli /usr/bin/php
    [ -d "/usr/lib/php8" ] && [ ! -d "/usr/lib/php" ] && ln -sf /usr/lib/php8 /usr/lib/php
    /etc/init.d/uhttpd restart
  }
}

# Configure TinyFM
setup_tinyfm() {
  log "STEP" "Configuring TinyFM"
  mkdir -p /www/tinyfm
  ln -sf / /www/tinyfm/rootfs
  chmod 755 /www/tinyfm
}

# Restore system information
restore_sysinfo() {
  log "STEP" "Restoring system info"
  [ -f "/etc/profile.d/30-sysinfo.sh-bak" ] && {
    mv /etc/profile.d/30-sysinfo.sh-bak /etc/profile.d/30-sysinfo.sh
    chmod +x /etc/profile.d/30-sysinfo.sh
  }
}

# Run secondary install
setup_secondary_install() {
  log "STEP" "Running secondary install"
  [ -f "/root/install2.sh" ] && {
    chmod +x /root/install2.sh
    /root/install2.sh >> "$LOGFILE" 2>&1
    check_command "Secondary install"
  }
}

# Complete setup
complete_setup() {
  log "STEP" "Setup Complete"
  log "INFO" "Summary: Hostname=RTA-WRT, LAN=192.168.1.1, Timezone=Asia/Jakarta"
  rm -rf /root/install2.sh /tmp/* 2>/dev/null
  rm -f /etc/uci-defaults/$(basename $0) 2>/dev/null
  echo "Final State:" >> "$LOGFILE"
  date >> "$LOGFILE"
  uptime >> "$LOGFILE"
  free -h >> "$LOGFILE"
  df -h >> "$LOGFILE"
  ifconfig | grep -E "^[a-z]|inet " >> "$LOGFILE"
  ls /etc/rc.d/S* | cut -d/ -f4 | sort >> "$LOGFILE"
  cp "$LOGFILE" "/root/setup_complete_$(date +%Y%m%d_%H%M%S).log"
  log "INFO" "Rebooting in 5 seconds"
  sync
  sleep 5
  reboot
}

# Main execution
main() {
  echo "=== RTA-WRT Router Setup v2.0 ==="
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

main