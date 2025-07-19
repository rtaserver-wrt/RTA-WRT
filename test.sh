#!/bin/bash
# Enhanced OpenWrt Image Builder Script
# Version: 3.0
# Description: Build custom OpenWrt firmware with enhanced features and improved reliability

set -euo pipefail

# Color codes for better output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script metadata
readonly SCRIPT_VERSION="3.0"
readonly SCRIPT_NAME="OpenWrt Image Builder"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration with defaults
readonly WORK_DIR="${PWD}/openwrt-build"
readonly BASE="${1:-openwrt}"
readonly BRANCH="${2:-24.10.2}"
readonly TARGET_SYSTEM="${3:-x86/64}"
readonly TARGET_NAME="${4:-x86-64}"
readonly PROFILE="${5:-generic}"
readonly ARCH="${6:-x86_64}"
readonly PACKAGES_INCLUDE="${7:-dnsmasq-full luci}"
readonly PACKAGES_EXCLUDE="${8:--dnsmasq}"
readonly CUSTOM_FILES_DIR="files"
readonly LOG_FILE="${WORK_DIR}/build.log"

# Advanced configuration options
ROOTFS_SIZE="1024" # Default rootfs size in MB
MAKE_JOBS=$(nproc)


# Enhanced logging function with file output
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$level] [$timestamp] $message"
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${NC} [$timestamp] $message" | tee -a "$LOG_FILE" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} [$timestamp] $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} [$timestamp] $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo "$log_entry" >> "$LOG_FILE" ;;
        "SUCCESS") echo -e "${CYAN}[SUCCESS]${NC} [$timestamp] $message" | tee -a "$LOG_FILE" ;;
    esac
}


# Determine Image Builder URL with improved error handling
get_image_builder_url() {
    local url
    case "$BASE" in
        "openwrt")
            url="https://downloads.openwrt.org/releases/$BRANCH/targets/$TARGET_SYSTEM/openwrt-imagebuilder-$BRANCH-$TARGET_NAME.Linux-x86_64.tar.zst"
            ;;
        "immortalwrt")
            url="https://downloads.immortalwrt.org/releases/$BRANCH/targets/$TARGET_SYSTEM/immortalwrt-imagebuilder-$BRANCH-$TARGET_NAME.Linux-x86_64.tar.zst"
            ;;
        *)
            log "ERROR" "Unsupported base '$BASE'. Supported: openwrt, immortalwrt"
            exit 1
            ;;
    esac
    echo "$url"
}

# Function to display enhanced header
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                   $SCRIPT_NAME v$SCRIPT_VERSION                    ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} ${GREEN}Build Started:${NC} $(date)"
    echo -e "${BLUE}║${NC} ${GREEN}Base System:${NC} $BASE ($BRANCH)"
    echo -e "${BLUE}║${NC} ${GREEN}Target:${NC} $TARGET_SYSTEM ($TARGET_NAME)"
    echo -e "${BLUE}║${NC} ${GREEN}Profile:${NC} $PROFILE"
    echo -e "${BLUE}║${NC} ${GREEN}Architecture:${NC} $ARCH"
    echo -e "${BLUE}║${NC} ${GREEN}Packages (+):${NC} $PACKAGES_INCLUDE"
    echo -e "${BLUE}║${NC} ${GREEN}Packages (-):${NC} ${PACKAGES_EXCLUDE:-none}"
    echo -e "${BLUE}║${NC} ${GREEN}Custom Files:${NC} $CUSTOM_FILES_DIR"
    echo -e "${BLUE}║${NC} ${GREEN}Parallel Jobs:${NC} $MAKE_JOBS"
    echo -e "${BLUE}║${NC} ${GREEN}Work Directory:${NC} $WORK_DIR"
    echo -e "${BLUE}║${NC} ${GREEN}Log File:${NC} $LOG_FILE"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

# Enhanced prerequisites check
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check disk space (minimum 4GB for safety)
    local available_space
    available_space=$(df "$PWD" | tail -1 | awk '{print $4}')
    local min_space=4194304  # 4GB in KB
    
    if [[ "$available_space" -lt "$min_space" ]]; then
        log "ERROR" "Insufficient disk space. Available: $((available_space/1024/1024))GB, Required: 4GB"
        exit 1
    fi
    
    # Check memory
    local available_memory
    available_memory=$(free -k | grep '^Mem:' | awk '{print $2}')
    local min_memory=1048576  # 1GB in KB
    
    if [[ "$available_memory" -lt "$min_memory" ]]; then
        log "WARN" "Low memory detected. Available: $((available_memory/1024))MB. Build may be slow."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 -W 5 google.com &> /dev/null; then
        log "ERROR" "No internet connectivity. Unable to download Image Builder."
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites check completed"
}

# Enhanced environment setup
setup_environment() {
    log "INFO" "Setting up build environment..."
    
    # Handle existing build directory
    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    
    # Create work directory structure
    mkdir -p "$WORK_DIR"/{patches,logs,tmp}
    cd "$WORK_DIR"
    
    # Set build environment variables
    export FORCE_UNSAFE_CONFIGURE=1
    export MAKEFLAGS="-j$MAKE_JOBS"
    
    log "SUCCESS" "Environment setup completed"
}

# Enhanced Image Builder download with retry logic
get_image_builder() {
    log "INFO" "Downloading Image Builder..."
    
    local image_builder_url
    image_builder_url=$(get_image_builder_url)
    local ib_file
    ib_file=$(basename "$image_builder_url")
    
    # Check if file already exists and verify integrity
    if [[ -f "$ib_file" ]]; then
        log "INFO" "Image Builder file exists: $ib_file"
        rm -f "$ib_file"
    fi
    
    # Download with retry logic
    if [[ ! -f "$ib_file" ]]; then
        log "INFO" "Downloading from: $image_builder_url"
        
        local retry_count=0
        local max_retries=3
        
        while [[ $retry_count -lt $max_retries ]]; do
            if wget --show-progress --timeout=60 --tries=1 "$image_builder_url"; then
                break
            else
                ((retry_count++))
                log "WARN" "Download failed, retry $retry_count/$max_retries"
                sleep 5
            fi
        done
        
        if [[ $retry_count -eq $max_retries ]]; then
            log "ERROR" "Failed to download Image Builder after $max_retries attempts"
            exit 1
        fi
    fi
    
    # Verify file integrity
    if [[ ! -s "$ib_file" ]]; then
        log "ERROR" "Downloaded file is empty or corrupted"
        exit 1
    fi
    
    # Extract with progress
    log "INFO" "Extracting Image Builder..."
    case "$ib_file" in
        *.tar.xz) tar -xJf "$ib_file" --strip-components=1 ;;
        *.tar.gz) tar -xzf "$ib_file" --strip-components=1 ;;
        *.tar.zst) tar -I zstd -xf "$ib_file" --strip-components=1 ;;
        *) 
            log "ERROR" "Unsupported archive format: $ib_file"
            exit 1
            ;;
    esac
    
    # Verify extraction
    if [[ ! -f "Makefile" ]]; then
        log "ERROR" "Image Builder extraction failed - Makefile not found"
        exit 1
    fi
    
    log "SUCCESS" "Image Builder extracted successfully"
}

# Enhanced custom files preparation
prepare_custom_files() {
    log "INFO" "Preparing custom files..."
    
    local source_files_dir="../$CUSTOM_FILES_DIR"
    
    if [[ -d "$source_files_dir" ]]; then
        log "INFO" "Copying custom files from $source_files_dir"
        
        # Create destination directory
        mkdir -p "$CUSTOM_FILES_DIR"
        
        # Copy files with proper permissions
        find "$source_files_dir" -type f -print0 | while IFS= read -r -d '' file; do
            local rel_path="${file#$source_files_dir/}"
            local dest_dir="$CUSTOM_FILES_DIR/$(dirname "$rel_path")"
            
            mkdir -p "$dest_dir"
            cp "$file" "$CUSTOM_FILES_DIR/$rel_path"
            
            # Set executable permissions for scripts
            if [[ "$file" == *.sh ]] || [[ "$file" == */bin/* ]]; then
                chmod +x "$CUSTOM_FILES_DIR/$rel_path"
            fi
        done
        
        # Count files
        local file_count
        file_count=$(find "$CUSTOM_FILES_DIR" -type f | wc -l)
        log "INFO" "Copied $file_count custom files"
        
    else
        log "WARN" "Custom files directory not found: $source_files_dir"
        mkdir -p "$CUSTOM_FILES_DIR"
    fi
    
    log "SUCCESS" "Custom files prepared"
}

# Enhanced package validation
validate_packages() {
    log "INFO" "Validating package configuration..."
    
    # Check for package conflicts
    local include_array=($PACKAGES_INCLUDE)
    local exclude_array=($PACKAGES_EXCLUDE)
    
    # Find conflicting packages
    local conflicts=()
    for pkg in "${include_array[@]}"; do
        for excl in "${exclude_array[@]}"; do
            if [[ "$pkg" == "$excl" ]]; then
                conflicts+=("$pkg")
            fi
        done
    done
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log "ERROR" "Package conflicts detected: ${conflicts[*]}"
        log "ERROR" "Package cannot be both included and excluded"
        exit 1
    fi
    
    # Validate package names (basic check)
    local invalid_packages=()
    for pkg in "${include_array[@]}"; do
        if [[ ! "$pkg" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            invalid_packages+=("$pkg")
        fi
    done
    
    if [[ ${#invalid_packages[@]} -gt 0 ]]; then
        log "WARN" "Potentially invalid package names: ${invalid_packages[*]}"
    fi
    
    log "INFO" "Package validation completed"
    log "INFO" "Packages to include: ${#include_array[@]}"
    log "INFO" "Packages to exclude: ${#exclude_array[@]}"
}

# Enhanced firmware patching
patch_firmware() {
    log "INFO" "Applying firmware patches..."
    
    log "SUCCESS" "Firmware patching completed"
}

# Enhanced build process
build_firmware() {
    log "INFO" "Starting firmware build process..."
    
    # Prepare build command
    local build_cmd="make image"
    build_cmd+=" PROFILE='$PROFILE'"
    build_cmd+=" PACKAGES='$PACKAGES_INCLUDE'"
    
    if [[ -n "$PACKAGES_EXCLUDE" ]]; then
        build_cmd+=" PACKAGES+=' $PACKAGES_EXCLUDE'"
    fi
    
    if [[ -d "$CUSTOM_FILES_DIR" ]] && [[ -n "$(ls -A "$CUSTOM_FILES_DIR" 2>/dev/null)" ]]; then
        build_cmd+=" FILES='$CUSTOM_FILES_DIR'"
    fi
    
    if [[ -n "$ROOTFS_SIZE" ]]; then
        build_cmd+=" EXTRA_IMAGE_NAME='rootfs-$ROOTFS_SIZE'"
    fi
    
    # Add parallel jobs
    build_cmd+=" -j$MAKE_JOBS"
    
    log "INFO" "Build command: $build_cmd"
    
    # Execute build with timing
    local build_start_time
    build_start_time=$(date +%s)
    
    log "INFO" "Starting build process..."
    if ! eval "$build_cmd" >>"$LOG_FILE" 2>&1; then
        tail -n 50 "$LOG_FILE"
        log "ERROR" "Firmware build failed"
        log "ERROR" "Check $LOG_FILE for detailed error information"
        exit 1
    fi
    
    local build_end_time
    build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))
    
    log "SUCCESS" "Build completed in $build_duration seconds ($(($build_duration/60))m $(($build_duration%60))s)"
}

# Enhanced results display
show_results() {
    log "SUCCESS" "Build completed successfully!"
    
    local bin_dir="bin/targets/$TARGET_SYSTEM"
    local images_found=0
    
    if [[ ! -d "$bin_dir" ]]; then
        log "ERROR" "Build directory not found: $bin_dir"
        return 1
    fi
    
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        BUILD RESULTS                           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    # Find and display firmware images
    while IFS= read -r -d '' image_file; do
        local filename
        filename=$(basename "$image_file")
        local filesize
        filesize=$(du -h "$image_file" | cut -f1)
        local checksum
        checksum=$(sha256sum "$image_file" | cut -d' ' -f1)
        
        echo -e "${GREEN}📦 $filename${NC}"
        echo -e "   ${BLUE}Size:${NC} $filesize"
        echo -e "   ${BLUE}SHA256:${NC} $checksum"
        echo -e "   ${BLUE}Path:${NC} $image_file"
        echo ""
        
        ((images_found++))
    done < <(find "$bin_dir" -type f \( -name "*.img.gz" -o -name "*.bin" -o -name "*.vmdk" -o -name "*.img" \) -print0)
    
    if [[ $images_found -eq 0 ]]; then
        log "WARN" "No firmware images found in $bin_dir"
        log "INFO" "Available files:"
        ls -la "$bin_dir" || true
    else
        log "SUCCESS" "Generated $images_found firmware image(s)"
    fi
    
    # Build summary
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                         BUILD SUMMARY                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${GREEN}Base System:${NC} $BASE $BRANCH"
    echo -e "${GREEN}Target:${NC} $TARGET_SYSTEM ($PROFILE)"
    echo -e "${GREEN}Architecture:${NC} $ARCH"
    echo -e "${GREEN}Work Directory:${NC} $WORK_DIR"
    echo -e "${GREEN}Log File:${NC} $LOG_FILE"
    echo -e "${GREEN}Build Completed:${NC} $(date)"
    echo -e "${GREEN}Images Found:${NC} $images_found"
    echo ""
}

# Enhanced cleanup function
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Build failed with exit code $exit_code"
        log "INFO" "Check $LOG_FILE for detailed error information"
    else
        log "SUCCESS" "Build completed successfully"
    fi
    
    # Optional cleanup of temporary files
    if [[ "$exit_code" -eq 0 ]] && [[ -d "$WORK_DIR/tmp" ]]; then
        rm -rf "$WORK_DIR/tmp"
    fi
    
    # Display log file location
    if [[ -f "$LOG_FILE" ]]; then
        log "INFO" "Full build log available at: $LOG_FILE"
    fi
}

# Signal handlers
handle_interrupt() {
    log "WARN" "Build interrupted by user"
    exit 130
}

# Main execution function
main() {
    # Setup signal handlers
    trap cleanup EXIT
    trap handle_interrupt INT TERM
    
    # Main build process
    print_header
    
    check_prerequisites
    setup_environment
    get_image_builder
    prepare_custom_files
    validate_packages
    patch_firmware
    build_firmware
    show_results
    
    log "SUCCESS" "All operations completed successfully!"
}

# Execute main function with all arguments
main "$@"