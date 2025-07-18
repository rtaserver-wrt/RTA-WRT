#!/bin/bash

. ./scripts/0-includes.sh

WORK_DIR="${WORK_DIR:-$PWD}"
cd "${WORK_DIR}" || exit 1
SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"  

TAG="$(firmware_id "TAG" "${VERSION}" "${SOURCE}")"
BRANCH="$(echo "${TAG}" | awk -F. '{print $1"."$2}')"

# Download function
time bash ./scripts/1-download_image.sh "$SOURCE" "$TARGET" "$VERSION"

# Download package lists
time bash ./scripts/2-download_package_lists.sh "$SOURCE" "$TARGET" "$VERSION"

# Apply patches
time bash ./scripts/3-diy1_patch.sh "$SOURCE" "$TARGET" "$VERSION"

# Apply miscellaneous configurations
time bash ./scripts/4-diy2_misc.sh "$SOURCE" "$TARGET" "$VERSION"

# Build the image
time bash ./scripts/5-build_image.sh "$SOURCE" "$TARGET" "$VERSION"

# Repack the OpenWrt image
time bash ./scripts/6-repack_openwrt.sh "$SOURCE" "$TARGET" "$VERSION"

# Rename the OpenWrt image
time bash ./scripts/7-rename_openwrt.sh "$SOURCE" "$TARGET" "$VERSION"