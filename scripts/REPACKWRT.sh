#!/bin/bash
#
# repackwrt - Script to repackage OpenWRT firmware for various boards
# 
# Usage: repackwrt [--OPHUB|--ULO] -t <target_board> -k <kernel_version>

# Source the include file containing common functions and variables
if [[ ! -f "./scripts/INCLUDE.sh" ]]; then
    echo "ERROR: INCLUDE.sh not found in ./scripts/" >&2
    exit 1
fi

set -o errexit  # Exit on error
set -o nounset  # Exit on unset variables
set -o pipefail # Exit if any command in a pipe fails

# Source includes
. ./scripts/INCLUDE.sh

# Define constants
readonly OPHUB_REPO="https://github.com/ophub/amlogic-s9xxx-openwrt/archive/refs/heads/main.zip"
readonly ULO_REPO="https://github.com/armarchindo/ULO-Builder/archive/refs/heads/main.zip"
readonly WORK_DIR="${GITHUB_WORKSPACE:-$(pwd)}/${WORKING_DIR:-}"

# Function to display usage information
show_usage() {
    cat << EOF
Usage: repackwrt [--OPHUB|--ULO] -t <target_board> -k <kernel_version>

Arguments:
  --OPHUB, --ophub    Use Ophub builder
  --ULO, --ulo        Use ULO builder
  -t, --target        Target board name
  -k, --kernel        Kernel version to use

Examples:
  repackwrt --OPHUB -t amlogic -k 5.15.100
  repackwrt --ULO -t s905x -k 6.1.10
EOF
    exit 1
}

# Function to clean up resources
cleanup() {
    local dir="${1:-}"
    
    if [[ -n "$dir" && -d "$dir" && "$dir" != "/" ]]; then
        log "INFO" "Cleaning up temporary files..."
        sudo rm -rf "$dir"
    fi
}

# Main function for repackaging firmware
repackwrt() {
    # Parse arguments
    local builder_type=""
    local target_board=""
    local target_kernel=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --OPHUB|--ULO|--ophub|--ulo)
                builder_type="$1"
                shift
                ;;
            -t|--target)
                if [[ -z "$2" || "$2" == -* ]]; then
                    error_msg "Missing argument for $1"
                    show_usage
                fi
                target_board="$2"
                shift 2
                ;;
            -k|--kernel)
                if [[ -z "$2" || "$2" == -* ]]; then
                    error_msg "Missing argument for $1"
                    show_usage
                fi
                target_kernel="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                error_msg "Unknown option: $1"
                show_usage
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$builder_type" ]]; then
        error_msg "Builder type (--OPHUB --ophub or --ULO --ulo) is required"
        show_usage
    fi
    
    if [[ -z "$target_board" ]]; then
        error_msg "Target board (-t) is required"
        show_usage
    fi
    
    if [[ -z "$target_kernel" ]]; then
        error_msg "Target kernel (-k) is required"
        show_usage
    fi


    # Check if WORK_DIR is set
    if [[ -z "$WORK_DIR" ]]; then
        error_msg "WORKING_DIR environment variable is not set"
        exit 1
    fi
    
    # Setup directories based on builder type
    local builder_dir output_dir repo_url builder_name
    if [[ "${builder_type,,}" == "--ophub" ]]; then
        builder_dir="${WORK_DIR}/amlogic-s9xxx-openwrt-main"
        repo_url="${OPHUB_REPO}"
        builder_name="Ophub"
    else
        builder_dir="${WORK_DIR}/ULO-Builder-main"
        repo_url="${ULO_REPO}"
        builder_name="UloBuilder"
    fi

    output_dir="${WORK_DIR}/compiled_images"
    
    # Create working directory if it doesn't exist
    mkdir -p "${WORK_DIR}"
    mkdir -p "${output_dir}"

    # Navigate to working directory
    log "INFO" "Changing to working directory: ${WORK_DIR}"
    if ! cd "${WORK_DIR}"; then
        error_msg "Failed to access working directory: ${WORK_DIR}"
        exit 1
    fi

    # Download and extract builder
    log "INFO" "Downloading ${builder_name}..."
    if ! ariadl "${repo_url}" "main.zip"; then
        error_msg "Failed to download ${builder_name}"
        exit 1
    fi

    log "INFO" "Extracting ${builder_name}..."
    if ! unzip -q main.zip; then
        error_msg "Failed to extract ${builder_name} archive"
        rm -f main.zip
        exit 1
    fi
    rm -f main.zip

    # Register cleanup handler for unexpected exits
    trap "cleanup ${builder_dir}" EXIT

    # Prepare builder directory
    if [[ "${builder_type,,}" == "--ophub" ]]; then
        mkdir -p "${builder_dir}/openwrt-armsr"
    else
        mkdir -p "${builder_dir}/rootfs"
    fi

    # Find and validate rootfs file
    log "INFO" "Searching for rootfs file..."
    local rootfs_pattern="${WORK_DIR}/compiled_images/*-rootfs.tar.gz"
    local rootfs_files=( ${rootfs_pattern} )
    
    if [[ ${#rootfs_files[@]} -eq 0 || ! -f "${rootfs_files[0]}" ]]; then
        error_msg "No rootfs file found matching pattern: ${rootfs_pattern}"
        exit 1
    elif [[ ${#rootfs_files[@]} -gt 1 ]]; then
        error_msg "Multiple rootfs files found, expected only one:"
        for file in "${rootfs_files[@]}"; do
            echo "  - $(basename "${file}")"
        done
        exit 1
    fi
    
    local rootfs_file="${rootfs_files[0]}"
    log "SUCCESS" "Found rootfs file: $(basename "${rootfs_file}")"

    # Copy rootfs file
    log "INFO" "Copying rootfs file..."
    local target_path
    if [[ "${builder_type,,}" == "--ophub" ]]; then
        target_path="${builder_dir}/openwrt-armsr/${BASE:-openwrt}-armsr-armv8-generic-rootfs.tar.gz"
    else
        target_path="${builder_dir}/rootfs/${BASE:-openwrt}-armsr-armv8-generic-rootfs.tar.gz"
    fi

    if ! cp -f "${rootfs_file}" "${target_path}"; then
        error_msg "Failed to copy rootfs file"
        exit 1
    else
        ls -lh "${target_path}"
        log "SUCCESS" "Rootfs file copied successfully"
    fi

    # Change to builder directory
    log "INFO" "Changing to builder directory: ${builder_dir}"
    if ! cd "${builder_dir}"; then
        error_msg "Failed to access builder directory: ${builder_dir}"
        exit 1
    fi

    # Run builder-specific operations
    local device_output_dir
    if [[ "${builder_type,,}" == "--ophub" ]]; then
        log "INFO" "Running OphubBuilder with settings:"
        log "INFO" "  Board: ${target_board}"
        log "INFO" "  Kernel: ${target_kernel}"
        
        if ! sudo ./remake -b "${target_board}" -k "${target_kernel}" -s 1024; then
            error_msg "OphubBuilder execution failed"
            exit 1
        fi
        device_output_dir="./openwrt/out"
    else
        # Apply ULO patches
        log "INFO" "Applying UloBuilder patches..."
        if [[ -f "./.github/workflows/ULO_Workflow.patch" ]]; then
            mv ./.github/workflows/ULO_Workflow.patch ./ULO_Workflow.patch
            if ! patch -p1 < ./ULO_Workflow.patch >/dev/null 2>&1; then
                log "WARNING" "Failed to apply UloBuilder patch"
            else
                log "SUCCESS" "UloBuilder patch applied successfully"
            fi
        else
            log "WARNING" "UloBuilder patch not found, continuing without it"
        fi

        # Run UloBuilder
        log "INFO" "Running UloBuilder with settings:"
        log "INFO" "  Board: ${target_board}"
        log "INFO" "  Kernel: ${target_kernel}"
        log "INFO" "  Rootfs: $(basename "${target_path}")"
        
        if ! sudo ./ulo -y -m "${target_board}" -r "$(basename "${target_path}")" -k "${target_kernel}" -s 1024; then
            error_msg "UloBuilder execution failed"
            exit 1
        fi
        device_output_dir="./out/${target_board}"
    fi

    # Verify and copy output files
    if [[ ! -d "${device_output_dir}" ]]; then
        error_msg "Builder output directory not found: ${device_output_dir}"
        exit 1
    fi

    log "INFO" "Copying firmware files to output directory..."
    if ! cp -rf "${device_output_dir}"/* "${output_dir}/"; then
        error_msg "Failed to copy firmware files to output directory"
        exit 1
    fi

    # Verify output files exist
    local output_file_count=$(ls -1 "${output_dir}"/* 2>/dev/null | wc -l)
    if [[ ${output_file_count} -eq 0 ]]; then
        error_msg "No firmware files found in output directory"
        exit 1
    fi

    # List the generated files
    log "SUCCESS" "Generated firmware files:"
    ls -lh "${output_dir}"/*
    
    log "SUCCESS" "Firmware repacking completed successfully!"
    
    # Cleanup is handled by the trap
}

# Main execution
if [[ ${#} -lt 3 ]]; then
    error_msg "Not enough arguments provided"
    show_usage
fi

# Execute the function with all passed arguments
repackwrt --"$1" -t "$2" -k "$3"