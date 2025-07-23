#!/bin/bash

# Script untuk mengkonversi semua file dalam folder dan subfolder ke format Unix (dos2unix)
# Pastikan dos2unix sudah terinstall: sudo apt-get install dos2unix

# Fungsi bantuan
show_help() {
    echo "Penggunaan: $0 [folder_target]"
    echo
    echo "Konversi semua file dalam folder dan subfolder ke format Unix"
    echo
    echo "Contoh:"
    echo "  $0 /path/ke/folder"
    echo "  $0 .  (untuk folder saat ini)"
    exit 0
}

# Cek apakah dos2unix terinstall
if ! command -v dos2unix &> /dev/null; then
    echo "Error: dos2unix tidak ditemukan. Silakan install terlebih dahulu:"
    echo "sudo apt-get install dos2unix"
    exit 1
fi

# Cek parameter
if [ "$#" -ne 1 ]; then
    show_help
fi

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

TARGET_DIR="$1"

# Validasi folder target
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Folder target tidak ditemukan: $TARGET_DIR"
    exit 1
fi

echo "Memulai konversi dos2unix untuk semua file dalam: $TARGET_DIR"
echo "Termasuk semua subfolder..."
echo

# Hitung total file yang akan diproses
TOTAL_FILES=$(find "$TARGET_DIR" -type f | wc -l)
echo "Total file yang akan diproses: $TOTAL_FILES"
echo

# Konversi semua file
COUNTER=0
find "$TARGET_DIR" -type f -print0 | while IFS= read -r -d '' file; do
    COUNTER=$((COUNTER+1))
    echo -ne "Memproses file $COUNTER/$TOTAL_FILES: ${file:0:60}..." $'\r'
    
    # Skip file biner dengan mengecek jika file adalah teks
    if file "$file" | grep -q text; then
        dos2unix "$file" > /dev/null 2>&1
    fi
done

echo
echo
echo "Konversi selesai! Total file diproses: $COUNTER"