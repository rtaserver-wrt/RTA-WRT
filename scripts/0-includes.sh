#!/bin/bash

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORK_DIR="${SCRIPT_DIR}/../work"

# Include
. "${SCRIPT_DIR}/json_reader.sh"

# Settings
MAX_PARALLEL=4
MAX_RETRIES=3
RETRY_DELAY=2
TIMEOUT=30
USER_AGENT="Mozilla/5.0 (Linux; x86_64) AppleWebKit/537.36"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize
init() {
    mkdir -p "$WORK_DIR"
}

# Logging
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message"
}

# Download function
download_file() {
    local url="$1"
    local output_dir="$2"
    local filename="${3:-$(basename "$url")}"
    local output_file="$output_dir/$filename"

    # Skip if file exists and has content
    if [[ -f "$output_file" && -s "$output_file" ]]; then
        log "INFO" "File already exists: $filename"
        return 0
    fi

    mkdir -p "$output_dir"
    log "INFO" "Downloading: $filename"

    # Try aria2c first
    if command -v aria2c &>/dev/null; then
        if aria2c \
            --dir="$output_dir" \
            --out="$filename" \
            --continue=true \
            --max-connection-per-server=4 \
            --split=4 \
            --retry-wait=$RETRY_DELAY \
            --max-tries=$MAX_RETRIES \
            --connect-timeout=$TIMEOUT \
            --user-agent="$USER_AGENT" \
            --allow-overwrite=true \
            --console-log-level=error \
            "$url" 2>/dev/null; then
            
            log "INFO" "Downloaded: $filename"
            return 0
        fi
    fi
    
    # Fallback to curl
    if curl -L \
        --max-time $((TIMEOUT * 2)) \
        --retry $MAX_RETRIES \
        --retry-delay $RETRY_DELAY \
        --user-agent "$USER_AGENT" \
        --connect-timeout $TIMEOUT \
        --fail \
        --silent \
        --output "$output_file" \
        "$url"; then
        
        log "INFO" "Downloaded: $filename"
        return 0
    else
        log "ERROR" "Failed to download: $filename"
        rm -f "$output_file"
        return 1
    fi
}

# Wait for any process to complete
wait_for_completion() {
    local -n pids_ref=$1
    local new_pids=()
    
    for pid in "${pids_ref[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            new_pids+=("$pid")
        fi
    done
    
    pids_ref=("${new_pids[@]}")
    
    if [[ ${#pids_ref[@]} -ge $MAX_PARALLEL ]]; then
        sleep 0.5
    fi
}

# Parallel download manager
parallel_download() {
    local -n urls=$1
    local output_dir="$2"
    local pids=()
    local results=()
    
    if [[ ${#urls[@]} -eq 0 ]]; then
        log "WARN" "No URLs to download"
        return 1
    fi
    
    log "INFO" "Starting download of ${#urls[@]} files"
    
    for i in "${!urls[@]}"; do
        local url="${urls[$i]}"
        
        # Wait if max parallel reached
        while [[ ${#pids[@]} -ge $MAX_PARALLEL ]]; do
            wait_for_completion pids
        done
        
        # Start download in background
        {
            local result_file="/tmp/dl_result_$$_$i"
            if download_file "$url" "$output_dir"; then
                echo "SUCCESS" > "$result_file"
            else
                echo "FAILED" > "$result_file"
            fi
        } &
        
        pids+=($!)
        results+=("/tmp/dl_result_$$_$i")
    done
    
    # Wait for all downloads
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Count results
    local success=0
    local failed=0
    
    for result_file in "${results[@]}"; do
        if [[ -f "$result_file" ]]; then
            if grep -q "SUCCESS" "$result_file" 2>/dev/null; then
                ((success++))
            else
                ((failed++))
            fi
            rm -f "$result_file"
        else
            ((failed++))
        fi
    done
    
    log "INFO" "Download complete: $success succeeded, $failed failed"
    return $([[ $failed -eq 0 ]] && echo 0 || echo 1)
}

# Fetch GitHub release assets
get_github_assets() {
    local api_url="$1"
    local temp_file=$(mktemp)
    
    if curl -sL \
        --max-time $TIMEOUT \
        --retry $MAX_RETRIES \
        -H "Accept: application/vnd.github.v3+json" \
        -H "User-Agent: $USER_AGENT" \
        -o "$temp_file" \
        "$api_url"; then
        
        if command -v jq &>/dev/null; then
            jq -r '.assets[]?.browser_download_url // empty' "$temp_file" 2>/dev/null
        else
            grep -o '"browser_download_url":"[^"]*' "$temp_file" | cut -d'"' -f4
        fi
    fi
    
    rm -f "$temp_file"
}

# Filter assets to match exact package name
filter_matching_assets() {
    local package_name="$1"
    local assets="$2"
    
    echo "$assets" | grep -E "\.(ipk|apk)$" | while IFS= read -r asset_url; do
        if [[ -n "$asset_url" ]]; then
            local filename=$(basename "$asset_url")
            
            # Check if filename starts with the exact package name followed by underscore, dot, or dash
            if [[ "$filename" =~ ^${package_name}[_.-] ]] || [[ "$filename" == "${package_name}.ipk" ]] || [[ "$filename" == "${package_name}.apk" ]]; then
                echo "$asset_url"
            fi
        fi
    done
}

# Process package list
process_packages() {
    local -n package_list="$1"
    local download_dir="$2"
    local download_urls=()
    
    log "INFO" "Processing ${#package_list[@]} packages"
    
    for entry in "${package_list[@]}"; do
        if [[ ! "$entry" =~ ^([^|]+)\|(.+)$ ]]; then
            log "ERROR" "Invalid format: $entry"
            continue
        fi
        
        local package_name="${BASH_REMATCH[1]}"
        local source_url="${BASH_REMATCH[2]}"
        
        log "INFO" "Processing: $package_name"
        
        if [[ "$source_url" == *"api.github.com"* ]]; then
            # GitHub API - get all relevant assets
            local assets
            if assets=$(get_github_assets "$source_url"); then
                # Filter assets to match exact package name
                local matching_assets
                matching_assets=$(filter_matching_assets "$package_name" "$assets")
                
                if [[ -n "$matching_assets" ]]; then
                    while IFS= read -r asset_url; do
                        if [[ -n "$asset_url" ]]; then
                            download_urls+=("$asset_url")
                            log "INFO" "Found matching asset: $(basename "$asset_url")"
                        fi
                    done <<< "$matching_assets"
                else
                    log "WARN" "No matching assets for: $package_name"
                fi
            else
                log "ERROR" "Failed to fetch GitHub API: $source_url"
            fi
        else
            # Direct URL or custom source
            download_urls+=("$source_url")
            log "INFO" "Added direct URL: $source_url"
        fi
    done
    
    if [[ ${#download_urls[@]} -eq 0 ]]; then
        log "WARN" "No download URLs found"
        return 1
    fi
    
    parallel_download download_urls "$download_dir"
}

# Cleanup
cleanup() {
    log "INFO" "Cleaning up..."
    local cleanup_pids=$(jobs -p)
    [[ -n "$cleanup_pids" ]] && kill $cleanup_pids 2>/dev/null || true
    rm -f /tmp/dl_result_$$_* 2>/dev/null || true
}


