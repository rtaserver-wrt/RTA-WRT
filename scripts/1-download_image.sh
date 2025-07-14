#!/bin/bash

. ./scripts/0-includes.sh.sh

cd "${WORK_DIR}" || exit 1

SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"
TAG="$(firmware_id "TAG" "${VERSION}" "${SOURCE}")"
BRANCH="$(echo "${TAG}" | awk -F. '{print $1"."$2}')"


# Download function
download_image() {
    local url=""

    case "$SOURCE" in
        "openwrt")
            case "$VERSION" in
                "stable") url="$(firmware_id "URL" "$VERSION" "$SOURCE")$(device "TARGET_SYSTEM" "$TARGET")/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-$(device_id "TARGET_NAME" "$TARGET").Linux-x86_64.tar.zst" ;;
                "snapshot") url="$(firmware_id "URL" "$VERSION" "$SOURCE")$(device_id "TARGET_SYSTEM" "$TARGET")/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-$(device_id "TARGET_NAME" "$TARGET").Linux-x86_64.tar.zst" ;;
                "old-stable") url="$(firmware_id "URL" "$VERSION" "$SOURCE")$(device_id "TARGET_SYSTEM" "$TARGET")/$SOURCE-imagebuilder-$(firmware_id "TAG" "$VERSION" "$SOURCE")-$(device_id "TARGET_NAME" "$TARGET").Linux-x86_64.tar.xz" ;;
                *) echo "Unknown OpenWrt version: $VERSION"; return 1 ;;
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

    echo "Downloading image from: $url"
    mkdir -p "$WORK_DIR"
    if ! wget -q -P "$WORK_DIR" "$url"; then
        echo "Failed to download image from $url"
        return 1
    fi

    echo "Extracting image..."
    local filename="$(basename "$url")"
    if [[ "$filename" == *.tar.zst ]]; then
        tar -I zstd -xf "$WORK_DIR/$filename" -C "$WORK_DIR"
    elif [[ "$filename" == *.tar.xz ]]; then
        tar -xf "$WORK_DIR/$filename" -C "$WORK_DIR"
    else
        echo "Unsupported archive format: $filename"
        return 1
    fi
}

trap cleanup EXIT INT TERM

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 3 ]]; then
        echo "Usage: $0 <source> <target> <version>"
        exit 1
    fi
    download_image "$@"
fi