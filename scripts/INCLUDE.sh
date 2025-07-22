#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail
IFS=$'\n\t'

# Global variables for configuration with improved type declaration
declare -A CONFIG
CONFIG=(
    ["MAX_RETRIES"]=3
    ["RETRY_DELAY"]=2
    ["SPINNER_INTERVAL"]=0.1
    ["DEBUG"]=false
    ["TIMEOUT_SECONDS"]=60
    ["CONNECTION_TIMEOUT"]=30
    ["PARALLEL_DOWNLOADS"]=4
)

# Cleanup function
cleanup() {
    printf "\e[?25h"  # Ensure cursor is visible
    kill $(jobs -p) 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup EXIT
trap 'error_msg "Script interrupted" $LINENO' INT TERM

# Enhanced color setup with dynamic terminal capability detection
setup_colors() {
    PURPLE="\033[95m"
    BLUE="\033[94m"
    GREEN="\033[92m"
    YELLOW="\033[93m"
    RED="\033[91m"
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    RESET="\033[0m"

    STEPS="[${PURPLE} STEPS ${RESET}]"
    INFO="[${BLUE} INFO ${RESET}]"
    SUCCESS="[${GREEN} SUCCESS ${RESET}]"
    WARNING="[${YELLOW} WARNING ${RESET}]"
    ERROR="[${RED} ERROR ${RESET}]"
    DEBUG="[${CYAN} DEBUG ${RESET}]"

    # Formatting
    CL=$(echo "\033[m")
    UL=$(echo "\033[4m")
    BOLD=$(echo "\033[1m")
    BFR="\\r\\033[K"
    HOLD=" "
    TAB="  "
}

# Enhanced logging function with file output
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%d-%m-%Y %H:%M:%S')
    
    # Log to file
    echo "[$timestamp] [$level] $message"
    
    # Output to console if not in quiet mode
    case "$level" in
        "ERROR")   echo -e "${ERROR} $message" >&2 ;;
        "STEPS")   echo -e "${STEPS} $message" ;;
        "WARNING") echo -e "${WARNING} $message" ;;
        "SUCCESS") echo -e "${SUCCESS} $message" ;;
        "INFO")    echo -e "${INFO} $message" ;;
        "DEBUG")   [[ "${CONFIG[DEBUG]}" == "true" ]] && echo -e "${DEBUG} $message" ;;
        *)         echo -e "${INFO} $message" ;;
    esac
}

error_msg() {
    local line_number=${2:-${BASH_LINENO[0]}}
    echo -e "${ERROR} ${1} (Line: ${line_number})" >&2
    echo "Call stack:" >&2
    local frame=0
    while caller $frame; do
        ((frame++))
    done >&2
    exit 1
}

# Enhanced spinner with better process management and animation
spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local colors=("\033[31m" "\033[33m" "\033[32m" "\033[36m" "\033[34m" "\033[35m")
    
    printf "\e[?25l"  # Hide cursor
    
    local timeout_counter=0
    local timeout_limit=$((${CONFIG[TIMEOUT_SECONDS]} * 10))
    
    while kill -0 $pid 2>/dev/null; do
        for ((i = 0; i < ${#frames[@]}; i++)); do
            printf "\r ${colors[i % ${#colors[@]}]}%s${RESET} %s" "${frames[i]}" "$message"
            sleep "${CONFIG[SPINNER_INTERVAL]}"
            
            ((timeout_counter++))
            if [[ $timeout_counter -ge $timeout_limit ]]; then
                printf "\r${WARNING} Operation timed out after ${CONFIG[TIMEOUT_SECONDS]} seconds\n"
                kill -9 $pid 2>/dev/null || true
                printf "\e[?25h"  # Show cursor
                return 124  # Return timeout error code
            fi
        done
    done
    
    printf "\e[?25h"  # Show cursor
    wait $pid  # Wait for process to finish and get exit status
    return $?
}

# Display a progress bar
progress_bar() {
    local current=$1
    local total=$2
    local title="${3:-Progress}"
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r${BLUE}${title}:${RESET} [${GREEN}"
    for ((i=0; i<completed; i++)); do printf "="; done
    printf ">${RESET}"
    for ((i=0; i<remaining; i++)); do printf " "; done
    printf "] ${percentage}%% (${current}/${total})"
    
    if [ $current -eq $total ]; then
        printf "\n"
    fi
}

# Enhanced command installation with better error handling
cmdinstall() {
    local cmd="$1"
    local desc="${2:-$cmd}"
    
    log "INFO" "Installing: $desc"
    
    # Create temporary file for output
    local temp_file=$(mktemp)
    
    # Run command in background and capture PID
    (eval "$cmd" > "$temp_file" 2>&1) &
    local cmd_pid=$!
    
    # Start spinner
    spinner $cmd_pid "Installing $desc..."
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log "SUCCESS" "$desc installed successfully"
        [ "${CONFIG[DEBUG]}" = true ] && cat "$temp_file" | while read -r line; do log "DEBUG" "$line"; done
    else
        log "ERROR" "Failed to install $desc (Exit code: $exit_code)"
        log "ERROR" "Command output:"
        cat "$temp_file" | while read -r line; do log "ERROR" "  $line"; done
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    return 0
}

# Check system resources
check_system_resources() {
    log "STEPS" "Checking system resources..."
    
    # Check available disk space
    local available_space=$(df -P . | awk 'NR==2 {print $4}')
    local min_required_space=$((500 * 1024))  # 500 MB in KB
    
    if [[ $available_space -lt $min_required_space ]]; then
        log "WARNING" "Low disk space: $(numfmt --to=iec-i --suffix=B $((available_space * 1024))). Recommended: 500MB"
    else
        log "SUCCESS" "Disk space: $(numfmt --to=iec-i --suffix=B $((available_space * 1024)))"
    fi
    
    # Check available memory
    if command -v free &>/dev/null; then
        local available_memory=$(free -m | awk 'NR==2 {print $7}')
        local min_required_memory=200  # 200 MB
        
        if [[ $available_memory -lt $min_required_memory ]]; then
            log "WARNING" "Low memory: ${available_memory}MB. Recommended: ${min_required_memory}MB"
        else
            log "SUCCESS" "Available memory: ${available_memory}MB"
        fi
    fi
    
    # Check CPU load
    if [[ -f /proc/loadavg ]]; then
        local cpu_load=$(cat /proc/loadavg | awk '{print $1}')
        local cpu_cores=$(nproc 2>/dev/null || echo 1)
        local load_per_core=$(awk "BEGIN {printf \"%.2f\", $cpu_load / $cpu_cores}")
        
        if (( $(echo "$load_per_core > 0.8" | bc -l) )); then
            log "WARNING" "High CPU load: ${load_per_core} per core"
        else
            log "SUCCESS" "CPU load: ${load_per_core} per core"
        fi
    fi
    
    log "SUCCESS" "System resource check completed"
}

# Enhanced dependency checking with version comparison
check_dependencies() {
    local -A dependencies=(
        ["aria2"]="aria2c --version | grep -oP 'aria2 version \K[\d\.]+'"
        ["curl"]="curl --version | grep -oP 'curl \K[\d\.]+'"
        ["tar"]="tar --version | grep -oP 'tar \K[\d\.]+'"
        ["gzip"]="gzip --version | grep -oP 'gzip \K[\d\.]+'"
        ["unzip"]="unzip -v | grep -oP 'UnZip \K[\d\.]+'"
        ["git"]="git --version | grep -oP 'git version \K[\d\.]+'"
        ["wget"]="wget --version | grep -oP 'GNU Wget \K[\d\.]+'"
        ["jq"]="jq --version | grep -oP 'jq-\K[\d\.]+'"
        ["bc"]="bc --version | grep -oP 'bc \K[\d\.]+' || echo 'bc present'"
    )
    
    log "STEPS" "Checking system dependencies..."
    
    # Check for sudo privileges
    if ! sudo -n true 2>/dev/null; then
        log "WARNING" "This script requires sudo privileges for package installation"
        if ! sudo true; then
            error_msg "Failed to obtain sudo privileges"
            return 1
        fi
    fi
    
    # Update package lists with error handling and progress indication
    log "INFO" "Updating package lists..."
    (sudo apt-get update -qq) &
    local update_pid=$!
    spinner $update_pid "Updating package lists..."
    
    if [ $? -ne 0 ]; then
        error_msg "Failed to update package lists"
        return 1
    fi
    
    local missing_pkgs=()
    local installed_pkgs=0
    local total_pkgs=${#dependencies[@]}
    
    # First pass - check what needs to be installed
    for pkg in "${!dependencies[@]}"; do
        local version_cmd="${dependencies[$pkg]}"
        if ! eval "$version_cmd" &>/dev/null; then
            missing_pkgs+=("$pkg")
        else
            ((installed_pkgs++))
            progress_bar $installed_pkgs $total_pkgs "Dependency check"
        fi
    done
    
    # Second pass - install missing packages
    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        log "INFO" "Installing ${#missing_pkgs[@]} missing dependencies..."
        
        for pkg in "${missing_pkgs[@]}"; do
            log "WARNING" "Installing $pkg..."
            
            (sudo apt-get install -y "$pkg") &
            local install_pid=$!
            spinner $install_pid "Installing $pkg..."
            
            if [ $? -ne 0 ]; then
                error_msg "Failed to install $pkg"
                return 1
            fi
            
            local version_cmd="${dependencies[$pkg]}"
            local installed_version
            
            if ! installed_version=$(eval "$version_cmd" 2>/dev/null); then
                error_msg "Failed to verify installation of $pkg"
                return 1
            fi
            
            log "SUCCESS" "Installed $pkg version $installed_version"
            ((installed_pkgs++))
            progress_bar $installed_pkgs $total_pkgs "Dependency check"
        done
    fi
    
    log "SUCCESS" "All dependencies are satisfied!"
    return 0
}

# Enhanced download function with retry mechanism and better error handling
ariadl() {
    if [ "$#" -lt 1 ]; then
       error_msg "Usage: ariadl <URL> [OUTPUT_FILE]"
        return 1
    fi

   log "STEPS" "Aria2 Downloader"

    local URL OUTPUT_FILE OUTPUT_DIR OUTPUT
    URL=$1
    local RETRY_COUNT=0
    local MAX_RETRIES=3

    if [ "$#" -eq 1 ]; then
        OUTPUT_FILE=$(basename "$URL")
        OUTPUT_DIR="."
    else
        OUTPUT=$2
        OUTPUT_DIR=$(dirname "$OUTPUT")
        OUTPUT_FILE=$(basename "$OUTPUT")
    fi

    if [ ! -d "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
    fi

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
       log "INFO" "Downloading: $URL (Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
        
        if [ -f "$OUTPUT_DIR/$OUTPUT_FILE" ]; then
            rm "$OUTPUT_DIR/$OUTPUT_FILE"
        fi
        
        aria2c -q -d "$OUTPUT_DIR" -o "$OUTPUT_FILE" "$URL"
        
        if [ $? -eq 0 ]; then
           log "SUCCESS" "Downloaded: $OUTPUT_FILE"
            return 0
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
               error_msg " Download failed. Retrying..."
                sleep 2
            fi
        fi
    done

   error_msg " Failed to download: $OUTPUT_FILE after $MAX_RETRIES attempts"
    return 1
}

# Parallel download implementation
parallel_download() {
    local -n urls_array=$1
    local output_dir="${2:-packages}"
    local max_parallel=${CONFIG[PARALLEL_DOWNLOADS]}
    local total_files=${#urls_array[@]}
    local completed=0
    local active=0
    local pids=()
    
    mkdir -p "$output_dir"
    log "STEPS" "Starting parallel download of $total_files files (max $max_parallel at once)"
    
    for url in "${urls_array[@]}"; do
        # Wait if we've reached max parallel downloads
        while [ $active -ge $max_parallel ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 ${pids[$i]} 2>/dev/null; then
                    unset pids[$i]
                    ((completed++))
                    ((active--))
                    progress_bar $completed $total_files "Downloads"
                fi
            done
            
            # If still at max, wait a bit
            if [ $active -ge $max_parallel ]; then
                sleep 0.5
            fi
        done
        
        # Start a new download
        local filename=$(basename "$url")
        local output="$output_dir/$filename"
        
        (ariadl "$url" "$output" > /dev/null 2>&1) &
        pids+=($!)
        ((active++))
        
        log "INFO" "Started download: $filename (PID: ${pids[-1]})"
    done
    
    # Wait for remaining downloads
    log "INFO" "Waiting for remaining downloads to complete..."
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null
        ((completed++))
        progress_bar $completed $total_files "Downloads"
    done
    
    log "SUCCESS" "Completed $completed/$total_files downloads"
    return 0
}

# Enhanced package downloader with improved URL handling and validation
download_packages() {
    local -n package_list="$1"  # Use nameref for array reference
    local download_dir="${2:-packages}"
    
    # Create download directory
    mkdir -p "$download_dir"
    log "STEPS" "Downloading packages to $download_dir"
    
    # Prepare download queue
    local download_queue=()
    local total_packages=${#package_list[@]}
    local processed=0
    
    # Helper function for downloading
    download_file() {
        local url="$1"
        local output="$2"
        local max_retries=${CONFIG[MAX_RETRIES]}
        local retry=0
        
        while [ $retry -lt $max_retries ]; do
            if ariadl "$url" "$output"; then
                return 0
            fi
            retry=$((retry + 1))
            log "WARNING" "Retry $retry/$max_retries for $output"
            sleep ${CONFIG[RETRY_DELAY]}
        done
        return 1
    }

    for entry in "${package_list[@]}"; do
        ((processed++))
        progress_bar $processed $total_packages "Analyzing packages"
        
        IFS="|" read -r filename base_url <<< "$entry"
        unset IFS
        
        if [[ -z "$filename" || -z "$base_url" ]]; then
            error_msg "Invalid entry format: $entry"
            continue
        fi

        local download_url=""
        
        # Handling GitHub source
        if [[ "$base_url" == *"api.github.com"* ]]; then
            log "INFO" "Processing GitHub API: $base_url"
            
            # Temporary file for response
            local temp_response=$(mktemp)
            
            # Use curl with proper headers
            curl -sL --max-time ${CONFIG[CONNECTION_TIMEOUT]} \
                 -H "Accept: application/vnd.github.v3+json" \
                 -o "$temp_response" \
                 "$base_url"
            
            if [ $? -ne 0 ] || [ ! -s "$temp_response" ]; then
                log "ERROR" "Failed to fetch data from GitHub API"
                rm -f "$temp_response"
                continue
            fi
            
            # Process with jq if available
            if command -v jq &>/dev/null; then
                if ! file_urls=$(jq -r '.assets[].browser_download_url' "$temp_response" 2>/dev/null); then
                    log "ERROR" "Failed to parse JSON from $base_url"
                    cat "$temp_response" | head -20 | while read line; do
                        log "DEBUG" "$line"
                    done
                    rm -f "$temp_response"
                    continue
                fi
            else
                # Fallback if jq is not available
                file_urls=$(grep -o 'browser_download_url":"[^"]*' "$temp_response" | cut -d'"' -f4)
            fi
            
            rm -f "$temp_response"
            
            download_url=$(echo "$file_urls" | grep -E '\.(ipk|apk)$' | grep -i "$filename" | sort -V | tail -1)
            
            if [ -z "$download_url" ]; then
                log "WARNING" "No matching package found for $filename in GitHub assets"
            else
                log "INFO" "Found package URL: $download_url"
            fi
        fi
        
        # Handling Custom source
        if [[ "$base_url" != *"api.github.com"* ]]; then
            log "INFO" "Processing custom source: $base_url"
            
            # Download and process page content directly
            local temp_page=$(mktemp)
            
            if ! curl -sL --max-time ${CONFIG[CONNECTION_TIMEOUT]} --retry 3 --retry-delay ${CONFIG[RETRY_DELAY]} -o "$temp_page" "$base_url"; then
                log "ERROR" "Failed to fetch page: $base_url"
                rm -f "$temp_page"
                continue
            fi
            
            local patterns=(
                "${filename}[^\"]*\.(ipk|apk)"
                "${filename}_.*\.(ipk|apk)"
                "${filename}.*\.(ipk|apk)"
            )
            
            for pattern in "${patterns[@]}"; do
                download_file=$(grep -oP "(?<=\")${pattern}(?=\")" "$temp_page" | sort -V | tail -n 1)
                if [ -n "$download_file" ]; then
                    download_url="${base_url}/${download_file}"
                    log "INFO" "Found package URL: $download_url"
                    break
                fi
            done
            
            rm -f "$temp_page"
            
            if [ -z "$download_url" ]; then
                log "WARNING" "No matching package found for $filename in custom source"
            fi
        fi

        if [ -z "$download_url" ]; then
            log "ERROR" "No matching package found for $filename"
            continue
        fi
        
        # Add to download queue
        download_queue+=("$download_url")
    done

    # Process download queue in parallel
    if [ ${#download_queue[@]} -eq 0 ]; then
        log "WARNING" "No packages found to download"
        return 1
    else
        log "INFO" "Queued ${#download_queue[@]} packages for download"
        parallel_download download_queue "$download_dir"
        
        # Verify downloads
        local successful=0
        for url in "${download_queue[@]}"; do
            local filename=$(basename "$url")
            if [ -f "$download_dir/$filename" ] && [ -s "$download_dir/$filename" ]; then
                ((successful++))
            fi
        done
        
        log "SUCCESS" "Successfully downloaded $successful/${#download_queue[@]} packages"
        return 0
    fi
}

# Initialize the script
setup_colors

# Main function
main() {
    # Display banner
    echo -e "${CYAN}===============================================${RESET}"
    echo -e "${BOLD}${MAGENTA}     Enhanced Package Downloader & Installer${RESET}"
    echo -e "${CYAN}===============================================${RESET}"
    echo -e "${BLUE}Starting execution: $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo ""
    
    # Start execution
    log "STEPS" "Initializing script"
    
    # Check system resources
    check_system_resources || log "WARNING" "System resource check failed"
}
main