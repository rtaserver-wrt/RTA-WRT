#!/bin/bash

readonly DEVICES_LIST_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../congigs/devices.json"
readonly FIRMWARE_LIST_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../configs/firmware.json"

# Fungsi yang diperbaiki untuk mendapatkan field device dengan inheritance dari parent
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
    
    # Jika field tidak ditemukan di child device, cari di parent
    result=$(jq -r --arg field "$field" --arg id "$target_id" '.[] | select(.DEVICES) | select(.DEVICES[] | .ID == $id) | .[$field] // empty' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    echo "N/A"
    return 1
}

# Fungsi yang diperbaiki untuk mendapatkan field device berdasarkan NAME dengan inheritance dari parent
get_device_field_by_name() {
    local field="$1"
    local target_name="$2"
    
    # Cek apakah field dan target_name tidak kosong
    if [ -z "$field" ] || [ -z "$target_name" ]; then
        echo "Error: Field dan NAME tidak boleh kosong" >&2
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
    local result=$(jq -r --arg field "$field" --arg name "$target_name" '.[] | select(.NAME == $name) | .[$field] // empty' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    # Jika tidak ditemukan, cari di dalam array DEVICES
    result=$(jq -r --arg field "$field" --arg name "$target_name" '.[] | select(.DEVICES) | .DEVICES[] | select(.NAME == $name) | .[$field] // empty' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    # Jika field tidak ditemukan di child device, cari di parent
    result=$(jq -r --arg field "$field" --arg name "$target_name" '.[] | select(.DEVICES) | select(.DEVICES[] | .NAME == $name) | .[$field] // empty' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    echo "N/A"
    return 1
}

# Fungsi alternatif yang lebih eksplisit untuk mendapatkan field dengan inheritance berdasarkan NAME
get_device_field_by_name_with_inheritance() {
    local field="$1"
    local target_name="$2"
    
    # Cek apakah field dan target_name tidak kosong
    if [ -z "$field" ] || [ -z "$target_name" ]; then
        echo "Error: Field dan NAME tidak boleh kosong" >&2
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
    local result=$(jq -r --arg field "$field" --arg name "$target_name" '.[] | select(.NAME == $name) | .[$field] // empty' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    # Cari di dalam array DEVICES, jika tidak ada coba ambil dari parent
    result=$(jq -r --arg field "$field" --arg name "$target_name" '
        .[] | select(.DEVICES) | 
        if (.DEVICES[] | select(.NAME == $name) | .[$field] // empty) != "" then
            (.DEVICES[] | select(.NAME == $name) | .[$field])
        else
            (select(.DEVICES[] | .NAME == $name) | .[$field] // empty)
        end
    ' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    echo "N/A"
    return 1
}

# Fungsi untuk mendapatkan semua informasi device berdasarkan NAME (termasuk parent info)
get_complete_device_info_by_name() {
    local target_name="$1"
    
    if [ -z "$target_name" ]; then
        echo "Error: Harap berikan NAME!" >&2
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
    
    # Cari di level utama
    local main_result=$(jq -r --arg name "$target_name" '.[] | select(.NAME == $name)' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$main_result" ] && [ "$main_result" != "null" ]; then
        echo "$main_result"
        return 0
    fi
    
    # Cari di dalam array DEVICES dan gabungkan dengan parent info
    local combined_result=$(jq -r --arg name "$target_name" '
        .[] | select(.DEVICES) | 
        if (.DEVICES[] | select(.NAME == $name)) then
            . as $parent | 
            (.DEVICES[] | select(.NAME == $name)) as $child |
            $parent + $child
        else
            empty
        end
    ' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$combined_result" ] && [ "$combined_result" != "null" ]; then
        echo "$combined_result"
        return 0
    fi
    
    echo "Device not found"
    return 1
}

# Fungsi alternatif yang lebih eksplisit untuk mendapatkan field dengan inheritance berdasarkan ID
get_device_field_with_inheritance() {
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
    
    # Cari di dalam array DEVICES, jika tidak ada coba ambil dari parent
    result=$(jq -r --arg field "$field" --arg id "$target_id" '
        .[] | select(.DEVICES) | 
        if (.DEVICES[] | select(.ID == $id) | .[$field] // empty) != "" then
            (.DEVICES[] | select(.ID == $id) | .[$field])
        else
            (select(.DEVICES[] | .ID == $id) | .[$field] // empty)
        end
    ' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    
    echo "N/A"
    return 1
}

# Fungsi untuk mendapatkan semua informasi device (termasuk parent info)
get_complete_device_info() {
    local target_id="$1"
    
    if [ -z "$target_id" ]; then
        echo "Error: Harap berikan ID!" >&2
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
    
    # Cari di level utama
    local main_result=$(jq -r --arg id "$target_id" '.[] | select(.ID == $id)' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$main_result" ] && [ "$main_result" != "null" ]; then
        echo "$main_result"
        return 0
    fi
    
    # Cari di dalam array DEVICES dan gabungkan dengan parent info
    local combined_result=$(jq -r --arg id "$target_id" '
        .[] | select(.DEVICES) | 
        if (.DEVICES[] | select(.ID == $id)) then
            . as $parent | 
            (.DEVICES[] | select(.ID == $id)) as $child |
            $parent + $child
        else
            empty
        end
    ' "$DEVICES_LIST_FILE" 2>/dev/null)
    
    if [ -n "$combined_result" ] && [ "$combined_result" != "null" ]; then
        echo "$combined_result"
        return 0
    fi
    
    echo "Device not found"
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
device_id() {
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

device_name() {
    local field="$1"
    local name="$2"
    
    if [ -z "$field" ]; then
        echo "Error: Harap berikan nama field!" >&2
        echo "Field yang tersedia: ID, NAME, PROFILE, TARGET_SYSTEM, TARGET_NAME, ARCH_1, ARCH_2, ARCH_3, TYPE, KERNEL, BUILDER" >&2
        return 1
    fi
    
    if [ -z "$name" ]; then
        echo "Error: Harap berikan ID!" >&2
        return 1
    fi
    
    get_device_field_by_name "$field" "$name"
}

# Fungsi untuk mendapatkan field firmware
firmware_id() {
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