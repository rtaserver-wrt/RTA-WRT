#!/bin/bash
# diy-part2.sh - Kustomisasi konfigurasi dan modifikasi

# Modifikasi versi default
sed -i 's/OpenWrt/MyWrt/g' package/lean/default-settings/files/zzz-default-settings

# Mengubah IP default
# sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# Menambahkan theme
git clone https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon


# Mengatur zona waktu
sed -i "s/'UTC'/'WIB-7'/g" package/base-files/files/bin/config_generate

# Menambahkan banner kustom
cat > package/base-files/files/etc/banner << 'EOF'
  __  __      __        __
 |  \/  |_   _\ \      / /_ __| |_
 | |\/| | | | |\ \ /\ / /| '__| __|
 | |  | | |_| | \ V  V / | |  | |_
 |_|  |_|\__, |  \_/\_/  |_|   \__|
         |___/
 
 OpenWrt Custom Build
 -----------------------------------------------------
 
EOF

echo "DIY part 2 completed successfully!"