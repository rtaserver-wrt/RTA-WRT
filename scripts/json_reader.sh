#!/bin/bash

readonly DEVICES_LIST_FILE="$CONFIGS_DIR/devices.json"
readonly FIRMWARE_LIST_FILE="$CONFIGS_DIR/firmware.json"

# Fungsi untuk mendapatkan field berdasarkan ID dari devices.json
get_device_field_by_id() {
    local field="$1"
    local target_id="$2"
    
    # Cek apakah field dan target_id tidak kosong
    if [ -z "$field" ] || [ -z "$target_id" ]; then
        echo "Error: Field dan ID tidak boleh kosong" >&2
        return 1
    fi
    
    # Cek apakah file devices.json ada
    if [ ! -f "$DEVICES_LIST_FILE" ]; then
        echo "Error: File devices.json tidak ditemukan di $DEVICES_LIST_FILE" >&2
        return 1
    fi
    
    # Cek apakah jq tersedia
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq tidak tersedia. Silakan install terlebih dahulu." >&2
        return 1
    fi
    
    # Cari di level utama terlebih dahulu
    local result=$(jq -r --arg field "$field" --arg id "$target_id" '.[] | select(.ID == $id) | .[$field] // empty' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    # Jika tidak ditemukan, cari di dalam array DEVICES
    result=$(jq -r --arg field "$field" --arg id "$target_id" '.[] | select(.DEVICES) | .DEVICES[] | select(.ID == $id) | .[$field] // empty' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    echo "N/A"
    return 1
}

# Fungsi untuk mendapatkan field berdasarkan ID dari firmware.json
get_firmware_field_by_id() {
    local field="$1"
    local target_id="$2"
    local firmware_type="$3"  # Parameter opsional untuk filter firmware
    
    # Cek apakah field dan target_id tidak kosong
    if [ -z "$field" ] || [ -z "$target_id" ]; then
        echo "Error: Field dan ID tidak boleh kosong" >&2
        return 1
    fi
    
    # Cek apakah file firmware.json ada
    if [ ! -f "$FIRMWARE_LIST_FILE" ]; then
        echo "Error: File firmware.json tidak ditemukan di $FIRMWARE_LIST_FILE" >&2
        return 1
    fi
    
    # Cek apakah jq tersedia
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq tidak tersedia. Silakan install terlebih dahulu." >&2
        return 1
    fi
    
    local result=""
    
    # Cari di level utama terlebih dahulu
    if [ -n "$firmware_type" ]; then
        # Dengan filter firmware type - perbaiki logika pencarian
        result=$(jq -r --arg field "$field" --arg id "$target_id" --arg type "$firmware_type" '.[] | select(.ID == $type) | select(.ID == $id) | .[$field] // empty' "$FIRMWARE_LIST_FILE" 2>/dev/null)
    else
        # Tanpa filter
        result=$(jq -r --arg field "$field" --arg id "$target_id" '.[] | select(.ID == $id) | .[$field] // empty' "$FIRMWARE_LIST_FILE" 2>/dev/null)
    fi
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    # Jika tidak ditemukan, cari di dalam array VERSION
    if [ -n "$firmware_type" ]; then
        # Dengan filter firmware type
        result=$(jq -r --arg field "$field" --arg id "$target_id" --arg type "$firmware_type" '.[] | select(.ID == $type) | .VERSION[]? | select(.ID == $id) | .[$field] // empty' "$FIRMWARE_LIST_FILE" 2>/dev/null)
    else
        # Tanpa filter
        result=$(jq -r --arg field "$field" --arg id "$target_id" '.[] | select(.VERSION) | .VERSION[]? | select(.ID == $id) | .[$field] // empty' "$FIRMWARE_LIST_FILE" 2>/dev/null)
    fi
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    echo "N/A"
    return 1
}

# Fungsi untuk mendapatkan field device
device() {
    local field="$1"
    local id="$2"
    
    if [ -z "$field" ]; then
        echo "Error: Harap berikan nama field!" >&2
        echo "Field yang tersedia: ID, NAME, PROFILE, TARGET_SYSTEM, TARGET_NAME, ARCH_1, ARCH_2, ARCH_3, TYPE, KERNEL, BUILDER" >&2
        return 1
    fi
    
    if [ -z "$id" ]; then
        echo "Error: Harap berikan ID!" >&2
        return 1
    fi
    
    get_device_field_by_id "$field" "$id"
}

# Fungsi untuk mendapatkan field firmware
firmware() {
    local field="$1"
    local id="$2"
    local firmware_type="$3"  # Parameter opsional untuk filter firmware
    
    if [ -z "$field" ]; then
        echo "Error: Harap berikan nama field!" >&2
        echo "Field yang tersedia: ID, NAME, URL, TAG, EXTIMG" >&2
        return 1
    fi
    
    if [ -z "$id" ]; then
        echo "Error: Harap berikan ID!" >&2
        return 1
    fi
    
    get_firmware_field_by_id "$field" "$id" "$firmware_type"
}