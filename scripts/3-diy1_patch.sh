#!/bin/bash

. ../scripts/0-includes.sh

WORK_DIR="${WORK_DIR:-$PWD}"
cd "${WORK_DIR}" || exit 1

SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"
TAG="$(firmware_id "TAG" "${VERSION}" "${SOURCE}")"
BRANCH="$(echo "${TAG}" | awk -F. '{print $1"."$2}')"

# Apply distribution-specific patches
apply_distro_patches() {
    case "${SOURCE}" in
        openwrt)
            log "INFO" "Applying OpenWrt-specific patches"
            ;;
        immortalwrt)
            log "INFO" "Applying ImmortalWrt-specific patches"
            log "INFO" "Removing default package: luci-app-cpufreq"
            sed -i "/luci-app-cpufreq/d" include/target.mk
            ;;
        *)
            log "WARN" "Unknown distribution: ${SOURCE}, skipping specific patches"
            ;;
    esac
}

# Patch package signature checking
patch_signature_check() {
    log "INFO" "Disabling package signature checking in repositories.conf"
    sed -i '\|option check_signature| s|^|#|' repositories.conf
}

# Patch Makefile for package installation
patch_makefile() {
    log "INFO" "Forcing package overwrite and downgrade during installation"
    sed -i 's|install \$(BUILD_PACKAGES)|install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade|' Makefile
}

# Configure partition sizes
configure_partitions() {
    log "INFO" "Setting kernel and rootfs partition sizes"
    sed -i 's|CONFIG_TARGET_KERNEL_PARTSIZE=.*|CONFIG_TARGET_KERNEL_PARTSIZE=128|' .config
    sed -i 's|CONFIG_TARGET_ROOTFS_PARTSIZE=.*|CONFIG_TARGET_ROOTFS_PARTSIZE=1024|' .config
}

# Apply Specific configurations
configure_config() {
    local type="$(device_id "TARGET_NAME" "${TARGET}")"
    case "${type}" in
        armsr-armv8)
            log "INFO" "Applying Amlogic-specific image options"
            local configs=(
                CONFIG_TARGET_ROOTFS_CPIOGZ
                CONFIG_TARGET_ROOTFS_EXT4FS
                CONFIG_TARGET_ROOTFS_SQUASHFS
                CONFIG_TARGET_IMAGES_GZIP
            )

            for config in "${configs[@]}"; do
                sed -i "s|${config}=.*|# ${config} is not set|" .config
            done
            ;;
        x86-64)
            log "INFO" "Applying x86_64-specific image options"
            sed -i 's|CONFIG_ISO_IMAGES=y|# CONFIG_ISO_IMAGES is not set|' .config
            sed -i 's|CONFIG_VHDX_IMAGES=y|# CONFIG_VHDX_IMAGES is not set|' .config
            ;;
        *)
            log "INFO" "Skipping Config"
            ;;
    esac
}

# Main execution flow
main() {
    apply_distro_patches
    patch_signature_check
    patch_makefile
    configure_partitions
    configure_config
    log "INFO" "Builder patch completed successfully!"
}

# Setup signal handlers
trap cleanup EXIT INT TERM

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi