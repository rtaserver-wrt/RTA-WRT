#!/bin/bash

. ../scripts/0-includes.sh

WORK_DIR="${WORK_DIR:-$PWD}"
cd "${WORK_DIR}" || exit 1

SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"
TAG="$(firmware_id "TAG" "${VERSION}" "${SOURCE}")"
BRANCH="$(echo "${TAG}" | awk -F. '{print $1"."$2}')"


# Download function
download_image() {
    local url=""
    local target_system
    local target_name
    
    # Validate device target first
    target_system=$(device_id "TARGET_SYSTEM" "$TARGET")
    if [ -z "$target_system" ]; then
        log "ERROR" "Invalid target system for: $TARGET"
        return 1
    fi
    
    target_name=$(device_id "TARGET_NAME" "$TARGET")
    if [ -z "$target_name" ]; then
        log "ERROR" "Invalid target name for: $TARGET"
        return 1
    fi
    
    case "$SOURCE" in
        "openwrt")
            case "$VERSION" in
                "stable") url="$(firmware_id "URL" "$VERSION" "$SOURCE")${target_system}/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-${target_name}.Linux-x86_64.tar.zst" ;;
                "snapshot") url="$(firmware_id "URL" "$VERSION" "$SOURCE")${target_system}/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-${target_name}.Linux-x86_64.tar.zst" ;;
                "old-stable") url="$(firmware_id "URL" "$VERSION" "$SOURCE")${target_system}/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-${target_name}.Linux-x86_64.tar.xz" ;;
                *) log "ERROR" "Unknown OpenWrt version: $VERSION"; return 1 ;;
            esac
            ;;
        "immortalwrt")
            case "$VERSION" in
                "stable") url="$(firmware_id "URL" "$VERSION" "$SOURCE")$(device_id "TARGET_SYSTEM" "$TARGET")/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-$(device_id "TARGET_NAME" "$TARGET").Linux-x86_64.tar.zst" ;;
                "snapshot") url="$(firmware_id "URL" "$VERSION" "$SOURCE")$(device_id "TARGET_SYSTEM" "$TARGET")/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-$(device_id "TARGET_NAME" "$TARGET").Linux-x86_64.tar.zst" ;;
                "old-stable") url="$(firmware_id "URL" "$VERSION" "$SOURCE")$(device_id "TARGET_SYSTEM" "$TARGET")/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-$(device_id "TARGET_NAME" "$TARGET").Linux-x86_64.tar.xz" ;;
                *) echo "Unknown ImmortalWrt version: $VERSION"; return 1 ;;
            esac
            ;;
        *) echo "Unknown source: $SOURCE"; return 1 ;;
    esac

    log "INFO" "Downloading image from: $url"
    mkdir -p "$WORK_DIR"
    
    # Use our download_file function from includes
    if ! download_file "$url" "$WORK_DIR"; then
        log "ERROR" "Failed to download image from $url"
        return 1
    fi

    log "INFO" "Extracting image..."
    local filename="$(basename "$url")"
    local extract_cmd=""
    
    # Check if required tools are installed
    if [[ "$filename" == *.tar.zst ]] && ! command -v zstd &>/dev/null; then
        log "ERROR" "zstd is required but not installed"
        return 1
    fi
    
    # Prepare extraction command
    if [[ "$filename" == *.tar.zst ]]; then
        extract_cmd="tar -I zstd -xf"
    elif [[ "$filename" == *.tar.xz ]]; then
        extract_cmd="tar -xf"
    else
        log "ERROR" "Unsupported archive format: $filename"
        return 1
    fi
    
    # Extract with progress feedback
    if ! $extract_cmd "$WORK_DIR/$filename" -C "$WORK_DIR" 2>&1 | while read -r line; do
        log "INFO" "Extracting: $line"
    done; then
        log "ERROR" "Failed to extract $filename"
        return 1
    fi
    
    # Cleanup downloaded archive
    log "INFO" "Cleaning up downloaded archive..."
    rm -f "$WORK_DIR/$filename"
}

trap cleanup EXIT INT TERM

# Validate inputs
validate_inputs() {
    # Validate source
    case "$SOURCE" in
        "openwrt"|"immortalwrt") ;;
        *) log "ERROR" "Invalid source: $SOURCE. Must be 'openwrt' or 'immortalwrt'"; return 1 ;;
    esac
    
    # Validate version
    case "$VERSION" in
        "stable"|"snapshot"|"old-stable") ;;
        *) log "ERROR" "Invalid version: $VERSION. Must be 'stable', 'snapshot' or 'old-stable'"; return 1 ;;
    esac
    
    # Validate target exists in devices.json
    if ! device_id "TARGET_NAME" "$TARGET" >/dev/null; then
        log "ERROR" "Invalid target: $TARGET. Target not found in devices configuration"
        return 1
    fi
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 3 ]]; then
        log "ERROR" "Usage: $0 <source> <target> <version>"
        exit 1
    fi
    
    if ! validate_inputs; then
        exit 1
    fi
    
    if ! download_image "$@"; then
        log "ERROR" "Failed to download and extract image"
        exit 1
    fi
    
    log "INFO" "Image download and extraction completed successfully"
fi