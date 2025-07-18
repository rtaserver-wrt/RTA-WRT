
#!/bin/bash
# Script: 3-diy1_patch.sh
# Fungsi: Menerapkan patch khusus pada source sebelum build.

set -e

# Determine script directory and include paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCLUDES_PATH="${SCRIPT_DIR}/0-includes.sh"

if [ ! -f "$INCLUDES_PATH" ]; then
    echo "ERROR: Required includes file not found: $INCLUDES_PATH"
    exit 1
fi

# Source includes
. "$INCLUDES_PATH"

# Setup working directory
WORK_DIR="${WORK_DIR:-$PWD}"
if ! cd "$WORK_DIR" 2>/dev/null; then
    log "ERROR" "Cannot change to working directory: $WORK_DIR"
    exit 1
fi

# Initialize variables
SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"

# Get firmware information
TAG="$(firmware_id "TAG" "${VERSION}" "${SOURCE}")"
if [ -z "$TAG" ]; then
    log "ERROR" "Could not determine firmware TAG"
    exit 1
fi

BRANCH="$(echo "${TAG}" | awk -F. '{print $1"."$2}')"
if [ -z "$BRANCH" ]; then
    log "ERROR" "Could not determine BRANCH from TAG: $TAG"
    exit 1
fi


ARCH="$(device_id "ARCH_2" "$TARGET")"
if [ -z "$ARCH" ]; then
    log "ERROR" "Could not determine architecture for target: $TARGET"
    exit 1
fi

# Backup a file before modifying it
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup"
        log "INFO" "Created backup: ${file}.backup"
        return 0
    else
        log "ERROR" "File not found: $file"
        return 1
    fi
}

# Safe sed operation with backup and validation
safe_sed() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"
    
    if [ ! -f "$file" ]; then
        log "ERROR" "File not found: $file"
        return 1
    fi
    
    backup_file "$file" || return 1
    
    if ! sed -i.tmp "$pattern" "$file"; then
        log "ERROR" "Failed to patch file: $file"
        mv "${file}.backup" "$file"
        rm -f "${file}.tmp"
        return 1
    fi
    
    rm -f "${file}.tmp"
    return 0
}

# Apply distribution-specific patches
apply_distro_patches() {
    case "${SOURCE}" in
        openwrt)
            log "INFO" "Applying OpenWrt-specific patches"
            # Add OpenWrt specific patches here if needed
            ;;
        immortalwrt)
            log "INFO" "Applying ImmortalWrt-specific patches"
            if [ -f "include/target.mk" ]; then
                log "INFO" "Removing default package: luci-app-cpufreq"
                if ! safe_sed "include/target.mk" "/luci-app-cpufreq/d" ""; then
                    log "ERROR" "Failed to remove luci-app-cpufreq"
                    return 1
                fi
            else
                log "ERROR" "target.mk not found"
                return 1
            fi
            ;;
        *)
            log "WARN" "Unknown distribution: ${SOURCE}, skipping specific patches"
            return 1
            ;;
    esac
    return 0
}

# Patch package signature checking
patch_signature_check() {
    if [ ! -f "repositories.conf" ]; then
        log "ERROR" "repositories.conf not found"
        return 1
    fi
    
    log "INFO" "Disabling package signature checking in repositories.conf"
    if ! safe_sed "repositories.conf" '\|option check_signature| s|^|#|' ""; then
        log "ERROR" "Failed to disable package signature checking"
        return 1
    fi
    return 0
}

# Patch Makefile for package installation
patch_makefile() {
    if [ ! -f "Makefile" ]; then
        log "ERROR" "Makefile not found"
        return 1
    fi
    
    log "INFO" "Forcing package overwrite and downgrade during installation"
    if ! safe_sed "Makefile" 's|install \$(BUILD_PACKAGES)|install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade|' ""; then
        log "ERROR" "Failed to patch Makefile"
        return 1
    fi
    return 0
}

# Configure partition sizes
configure_partitions() {
    if [ ! -f ".config" ]; then
        log "ERROR" ".config not found"
        return 1
    fi
    
    log "INFO" "Setting kernel and rootfs partition sizes"
    local configs=(
        's|CONFIG_TARGET_KERNEL_PARTSIZE=.*|CONFIG_TARGET_KERNEL_PARTSIZE=128|'
        's|CONFIG_TARGET_ROOTFS_PARTSIZE=.*|CONFIG_TARGET_ROOTFS_PARTSIZE=1024|'
    )
    
    for config in "${configs[@]}"; do
        if ! safe_sed ".config" "$config" ""; then
            log "ERROR" "Failed to configure partition sizes"
            return 1
        fi
    done
    return 0
}

# Apply Specific configurations
configure_config() {
    if [ ! -f ".config" ]; then
        log "ERROR" ".config not found"
        return 1
    }

    local type="$(device_id "TARGET_NAME" "${TARGET}")"
    if [ -z "$type" ]; then
        log "ERROR" "Could not determine target type"
        return 1
    fi

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
                if ! safe_sed ".config" "s|${config}=.*|# ${config} is not set|" ""; then
                    log "ERROR" "Failed to configure ${config}"
                    return 1
                fi
            done
            ;;
        x86-64)
            log "INFO" "Applying x86_64-specific image options"
            local configs=(
                's|CONFIG_ISO_IMAGES=y|# CONFIG_ISO_IMAGES is not set|'
                's|CONFIG_VHDX_IMAGES=y|# CONFIG_VHDX_IMAGES is not set|'
            )
            
            for config in "${configs[@]}"; do
                if ! safe_sed ".config" "$config" ""; then
                    log "ERROR" "Failed to configure x86_64 options"
                    return 1
                fi
            done
            ;;
        *)
            log "INFO" "No specific configurations for target type: $type"
            ;;
    esac
    return 0
}

# Validate environment
validate_env() {
    local required_files=("repositories.conf" "Makefile" ".config")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        log "ERROR" "Missing required files: ${missing_files[*]}"
        return 1
    fi
    
    return 0
}

# Main execution flow
main() {
    log "INFO" "Starting builder patch process"
    
    if ! validate_env; then
        log "ERROR" "Environment validation failed"
        return 1
    fi
    
    local steps=(
        "apply_distro_patches"
        "patch_signature_check"
        "patch_makefile"
        "configure_partitions"
        "configure_config"
    )
    
    local failed_steps=()
    
    for step in "${steps[@]}"; do
        log "INFO" "Executing: $step"
        if ! $step; then
            log "ERROR" "Step failed: $step"
            failed_steps+=("$step")
        fi
    done
    
    if [ ${#failed_steps[@]} -gt 0 ]; then
        log "ERROR" "The following steps failed: ${failed_steps[*]}"
        return 1
    fi
    
    log "INFO" "Builder patch completed successfully!"
    return 0
}

# Setup signal handlers
trap cleanup EXIT INT TERM

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if ! main "$@"; then
        log "ERROR" "Build patch process failed"
        exit 1
    fi
fi