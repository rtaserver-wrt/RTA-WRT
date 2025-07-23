#!/bin/bash

# dos2unix converter
# Author: RTA-WRT

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

# Spinner characters
readonly SPINNER_CHARS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_PID=""

# Enhanced progress bar function
show_progress() {
    local current=$1
    local total=$2
    local file_name="$3"
    local width=40
    local percentage=0
    local filled=0
    local empty=0
    
    # Prevent division by zero
    if [[ $total -gt 0 ]]; then
        percentage=$((current * 100 / total))
        filled=$((current * width / total))
        empty=$((width - filled))
    fi
    
    # Clear the entire line first
    printf "\r\033[K"
    
    # Build progress bar
    local bar=""
    local i=0
    while [[ $i -lt $filled ]]; do
        bar+="█"
        i=$((i + 1))
    done
    while [[ $i -lt $width ]]; do
        bar+="░"
        i=$((i + 1))
    done
    
    # Display progress with file info
    printf "${CYAN}Progress:${RESET} [${GREEN}%s${RESET}] ${BOLD}%3d%%${RESET} ${GRAY}(%d/%d)${RESET}" \
           "$bar" "$percentage" "$current" "$total"
    
    # Add current file name if provided
    if [[ -n "$file_name" ]] && [[ ${#file_name} -lt 30 ]]; then
        printf " ${DIM}%s${RESET}" "$file_name"
    elif [[ -n "$file_name" ]]; then
        printf " ${DIM}...%s${RESET}" "${file_name: -27}"
    fi
    
    # Force output
    printf "%s" ""
}

# Enhanced spinner function
start_spinner() {
    local message="$1"
    local delay=0.1
    local i=0
    
    while true; do
        printf "\r${PURPLE}${SPINNER_CHARS[i]}${RESET} $message"
        i=$(((i + 1) % ${#SPINNER_CHARS[@]}))
        sleep $delay
    done &
    SPINNER_PID=$!
}

stop_spinner() {
    if [[ -n $SPINNER_PID ]]; then
        kill $SPINNER_PID 2>/dev/null
        wait $SPINNER_PID 2>/dev/null
        SPINNER_PID=""
        printf "\r%*s\r" 80 ""  # Clear the line
    fi
}

# Cleanup function
cleanup() {
    stop_spinner
    printf "\n${YELLOW}⚠️  Operation interrupted by user${RESET}\n"
    exit 130
}

# Set trap for cleanup
trap cleanup INT TERM

# Enhanced help function
show_help() {
    cat << EOF
${BOLD}${CYAN}📄 Modern dos2unix Converter v2.0${RESET}

${BOLD}USAGE:${RESET}
    $0 [OPTIONS] [target_directory]

${BOLD}DESCRIPTION:${RESET}
    Converts all text files in the specified directory and subdirectories 
    to Unix format with modern UI, progress tracking, and enhanced features.

${BOLD}OPTIONS:${RESET}
    ${GREEN}-h, --help${RESET}        Show this help message
    ${GREEN}-v, --verbose${RESET}     Enable verbose output
    ${GREEN}-q, --quiet${RESET}       Suppress non-error output
    ${GREEN}--dry-run${RESET}         Show what would be done without making changes
    ${GREEN}--exclude-git${RESET}     Exclude .git directories (default)
    ${GREEN}--include-hidden${RESET}  Include hidden files and directories

${BOLD}EXAMPLES:${RESET}
    $0 /path/to/directory
    $0 --verbose .
    $0 --dry-run ~/projects
    $0 --quiet /home/user/documents

${BOLD}FEATURES:${RESET}
    • ${GREEN}✓${RESET} Modern colorful interface
    • ${GREEN}✓${RESET} Real-time progress tracking
    • ${GREEN}✓${RESET} Animated spinner during processing
    • ${GREEN}✓${RESET} Enhanced error logging
    • ${GREEN}✓${RESET} Dry-run capability
    • ${GREEN}✓${RESET} Performance optimizations

EOF
    exit 0
}

# Enhanced banner
show_banner() {
    printf "${BOLD}${CYAN}"
    cat << "EOF"
██████╗  ██████╗ ███████╗██████╗ ██╗   ██╗███╗   ██╗██╗██╗  ██╗
██╔══██╗██╔═══██╗██╔════╝╚════██╗██║   ██║████╗  ██║██║╚██╗██╔╝
██║  ██║██║   ██║███████╗ █████╔╝██║   ██║██╔██╗ ██║██║ ╚███╔╝ 
██║  ██║██║   ██║╚════██║██╔═══╝ ██║   ██║██║╚██╗██║██║ ██╔██╗ 
██████╔╝╚██████╔╝███████║███████╗╚██████╔╝██║ ╚████║██║██╔╝ ██╗
╚═════╝  ╚═════╝ ╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝
EOF
    printf "${RESET}\n"
}

# Check dependencies with enhanced output
check_dependencies() {
    printf "${BLUE}🔍 Checking dependencies...${RESET}\n"
    
    local missing_deps=()
    
    for cmd in dos2unix file find; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        printf "${RED}❌ Missing dependencies: ${BOLD}${missing_deps[*]}${RESET}\n\n"
        printf "${YELLOW}📦 Installation commands:${RESET}\n"
        printf "  ${GRAY}Debian/Ubuntu:${RESET} sudo apt install ${missing_deps[*]}\n"
        printf "  ${GRAY}CentOS/RHEL:${RESET}   sudo yum install ${missing_deps[*]}\n"
        printf "  ${GRAY}macOS:${RESET}         brew install ${missing_deps[*]}\n"
        exit 1
    fi
    
    printf "${GREEN}✅ All dependencies satisfied${RESET}\n\n"
}

# Parse arguments
parse_args() {
    VERBOSE=false
    QUIET=false
    DRY_RUN=false
    EXCLUDE_GIT=true
    INCLUDE_HIDDEN=false
    TARGET_DIR=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --exclude-git)
                EXCLUDE_GIT=true
                shift
                ;;
            --include-hidden)
                INCLUDE_HIDDEN=true
                shift
                ;;
            -*)
                printf "${RED}❌ Unknown option: $1${RESET}\n"
                printf "Use ${CYAN}--help${RESET} for usage information.\n"
                exit 1
                ;;
            *)
                if [[ -z $TARGET_DIR ]]; then
                    TARGET_DIR="$1"
                else
                    printf "${RED}❌ Multiple directories specified${RESET}\n"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Default to current directory if none specified
    [[ -z $TARGET_DIR ]] && TARGET_DIR="."
}

# Enhanced directory validation
validate_directory() {
    if [[ ! -d "$TARGET_DIR" ]]; then
        printf "${RED}❌ Directory '${BOLD}$TARGET_DIR${RESET}${RED}' does not exist${RESET}\n"
        exit 1
    fi
    
    if [[ ! -r "$TARGET_DIR" ]]; then
        printf "${RED}❌ Directory '${BOLD}$TARGET_DIR${RESET}${RED}' is not readable${RESET}\n"
        exit 1
    fi
    
    # Resolve absolute path
    TARGET_DIR=$(realpath "$TARGET_DIR" 2>/dev/null || readlink -f "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")
    
    [[ $QUIET == false ]] && printf "${CYAN}📁 Target directory: ${BOLD}$TARGET_DIR${RESET}\n"
    
    # Check for Windows mount points
    case "$TARGET_DIR" in
        /mnt/*|/media/*)
            [[ $QUIET == false ]] && printf "${YELLOW}⚠️  Windows filesystem detected - performance may be slower${RESET}\n"
            ;;
    esac
}

# Build find command with options
build_find_command() {
    local find_cmd="find '$TARGET_DIR' -type f -not -type l"
    
    if [[ $EXCLUDE_GIT == true ]]; then
        find_cmd="$find_cmd -not -path '*/.git/*'"
    fi
    
    if [[ $INCLUDE_HIDDEN == false ]]; then
        find_cmd="$find_cmd -not -path '*/.*'"
    fi
    
    echo "$find_cmd"
}

# Enhanced file processing with better progress updates
process_files() {
    local find_cmd
    find_cmd=$(build_find_command)
    
    [[ $QUIET == false ]] && start_spinner "🔍 Scanning files..."
    
    local file_list
    file_list=$(eval "$find_cmd" 2>/dev/null)
    local total_files
    total_files=$(echo "$file_list" | grep -c '^' 2>/dev/null || echo 0)
    
    stop_spinner
    
    if [[ $total_files -eq 0 ]]; then
        printf "${YELLOW}⚠️  No files found in the specified directory${RESET}\n"
        exit 0
    fi
    
    [[ $QUIET == false ]] && printf "${BLUE}📊 Found ${BOLD}$total_files${RESET}${BLUE} files to analyze${RESET}\n\n"
    
    # Setup logging
    local error_log="$TARGET_DIR/dos2unix_$(date +%Y%m%d_%H%M%S).log"
    if ! touch "$error_log" 2>/dev/null; then
        error_log="/tmp/dos2unix_$(date +%Y%m%d_%H%M%S).log"
        [[ $QUIET == false ]] && printf "${YELLOW}⚠️  Using temporary log file: $error_log${RESET}\n"
    fi
    
    # Processing counters
    local counter=0
    local converted=0
    local skipped=0
    local errors=0
    local last_update=0
    
    # Process files
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        counter=$((counter + 1))
        local relative_path="${file#$TARGET_DIR/}"
        [[ "$relative_path" == "$file" ]] && relative_path="$(basename "$file")"
        
        # Update progress more frequently and smoothly
        if [[ $QUIET == false ]] && [[ $VERBOSE == false ]]; then
            # Update every file or every 10 files for large datasets
            if [[ $((counter - last_update)) -ge 1 ]] || [[ $total_files -lt 100 ]] || [[ $counter -eq $total_files ]]; then
                show_progress "$counter" "$total_files" "$relative_path"
                last_update=$counter
                # Small delay to make progress visible
                [[ $total_files -gt 50 ]] && sleep 0.01
            fi
        fi
        
        # Check file permissions
        if [[ ! -r "$file" ]] || [[ ! -w "$file" ]]; then
            [[ $VERBOSE == true ]] && printf "${YELLOW}⚠️  Skipped (permissions): $relative_path${RESET}\n"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] PERMISSION_DENIED: $file" >> "$error_log"
            skipped=$((skipped + 1))
            continue
        fi
        
        # Check if file is text
        if file -b --mime-type "$file" 2>/dev/null | grep -q '^text/'; then
            if [[ $DRY_RUN == true ]]; then
                [[ $VERBOSE == true ]] && printf "${CYAN}📝 Would convert: $relative_path${RESET}\n"
                converted=$((converted + 1))
            else
                if dos2unix "$file" >> "$error_log" 2>&1; then
                    [[ $VERBOSE == true ]] && printf "${GREEN}✅ Converted: $relative_path${RESET}\n"
                    converted=$((converted + 1))
                else
                    [[ $VERBOSE == true ]] && printf "${RED}❌ Failed: $relative_path${RESET}\n"
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] CONVERSION_FAILED: $file" >> "$error_log"
                    errors=$((errors + 1))
                fi
            fi
        else
            [[ $VERBOSE == true ]] && printf "${GRAY}⏭️  Skipped (binary): $relative_path${RESET}\n"
            skipped=$((skipped + 1))
        fi
        
        # Force terminal update for smoother progress
        [[ $QUIET == false ]] && [[ $VERBOSE == false ]] && tput flush 2>/dev/null
        
    done <<< "$file_list"
    
    # Final progress update - ensure 100% is shown
    [[ $QUIET == false ]] && [[ $VERBOSE == false ]] && show_progress "$total_files" "$total_files" "Complete!"
    
    # Clear progress line and move to next line
    printf "\n\n"
    
    # Summary
    show_summary "$counter" "$converted" "$skipped" "$errors" "$error_log"
}

# Enhanced summary display
show_summary() {
    local total=$1
    local converted=$2
    local skipped=$3
    local errors=$4
    local log_file=$5
    
    printf "${BOLD}${CYAN}📋 CONVERSION SUMMARY${RESET}\n"
    printf "${CYAN}══════════════════════════════════════${RESET}\n"
    printf "${BLUE}📁 Total files analyzed:${RESET} ${BOLD}%d${RESET}\n" "$total"
    printf "${GREEN}✅ Files converted:${RESET}      ${BOLD}%d${RESET}\n" "$converted"
    printf "${YELLOW}⏭️  Files skipped:${RESET}        ${BOLD}%d${RESET}\n" "$skipped"
    printf "${RED}❌ Errors encountered:${RESET}   ${BOLD}%d${RESET}\n" "$errors"
    
    if [[ $DRY_RUN == true ]]; then
        printf "\n${YELLOW}🔍 DRY RUN MODE - No files were actually modified${RESET}\n"
    fi
    
    if [[ $errors -gt 0 ]]; then
        printf "\n${RED}📋 Error details logged to: ${BOLD}$log_file${RESET}\n"
    else
        # Remove empty log file
        [[ -f "$log_file" ]] && [[ ! -s "$log_file" ]] && rm -f "$log_file" 2>/dev/null
    fi
    
    printf "\n${GREEN}🎉 Operation completed successfully!${RESET}\n"
}

# Main execution
main() {
    show_banner
    parse_args "$@"
    check_dependencies
    validate_directory
    process_files
}

# Execute main function
main "$@"