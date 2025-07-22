#!/usr/bin/env bash

# --- Configuration ---
# Set these environment variables before running the script
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
THREAD_ID="${THREAD_ID:-}" # Optional, for group chats

# Build specific variables
SOURCE="${SOURCE}"             # e.g., "immortalwrt", "openwrt"
VERSION="${VERSION}"           # Firmware version
FOR="${FOR}"                   # "main" for stable release, anything else for dev build
RELEASE_TAG="${RELEASE_TAG}"   # GitHub release tag, if applicable

# --- Functions ---

# Function to validate essential environment variables
validate_env_vars() {
    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        echo "::error::BOT_TOKEN or CHAT_ID is not set. Please provide these variables."
        exit 1
    fi
}

# Function to set image/sticker URL based on source
get_theme_image_url() {
    local source_type="$1"
    if [[ "$source_type" = "immortalwrt" ]]; then
        echo "https://avatars.githubusercontent.com/u/53193414?s=200&v=4" # ImmortalWRT theme
    else
        echo "https://avatars.githubusercontent.com/u/2528830?s=200&v=4"   # OpenWRT theme
    fi
}

# Function to get current date, time, and time of day
get_time_info() {
    CURRENT_DATE=$(date '+%d %B %Y')
    CURRENT_TIME=$(date '+%H:%M:%S %Z')
    HOUR=$(date '+%H')

    if [[ $HOUR -ge 5 && $HOUR -lt 12 ]]; then
        TIME_OF_DAY="morning"
        TIME_EMOJI="🌅"
    elif [[ $HOUR -ge 12 && $HOUR -lt 18 ]]; then
        TIME_OF_DAY="afternoon"
        TIME_EMOJI="☀️"
    else
        TIME_OF_DAY="evening"
        TIME_EMOJI="🌙"
    fi
}

# Function to extract and format changelog from CHANGELOG.md
extract_changelog() {
    local changelog_file="CHANGELOG.md"
    local today_date=$(date '+%d-%m-%Y') # e.g., 20-05-2025

    CHANGELOG_FULL=""
    CHANGELOG=""

    if [[ -f "$changelog_file" ]]; then
        # Extract the full changelog section for the given date
        CHANGELOG_FULL=$(awk -v today="$today_date" '
            BEGIN { RS="\n"; print_changelog=0 }
            /\*\*Changelog Firmware\*\*/ {
                if ($0 ~ today) {
                    print_changelog=1
                } else if (print_changelog) {
                    print_changelog=0
                }
            }
            print_changelog && /^\- / && !/Version:/ {
                sub(/^- /, "│ • ")
                print
            }
        ' "$changelog_file")

        # Truncate changelog for Telegram caption (max 5 entries)
        CHANGELOG=$(echo "$CHANGELOG_FULL" | head -n 5)
        if [[ $(echo "$CHANGELOG_FULL" | wc -l) -gt 5 ]]; then
            CHANGELOG+="\n│ • And More..."
        fi
    else
        echo "Debug: CHANGELOG.md not found in current directory."
    fi

    # Fallback if no changelog found
    if [[ -z "$CHANGELOG_FULL" ]]; then
        CHANGELOG="│ • No changelog entries found for version ${VERSION} on date ${today_date}. Verify CHANGELOG.md format and version."
        CHANGELOG_FULL="$CHANGELOG"
    fi
}

# Function to generate the Telegram message caption
generate_telegram_caption() {
    local message_type="$1" # "main" or "dev"
    local changelog_content="$2"

    local title_block
    local section_title
    local tips_guidelines_title
    local tips_guidelines_content

    if [[ "$message_type" = "main" ]]; then
        title_block="╔══════════════════════╗
          🎯 RTA-WRT FIRMWARE
               ✅ STABLE RELEASE
╚══════════════════════╝"
        section_title="📌 *Release Highlights*"
        tips_guidelines_title="💡 *Installation Tips*"
        tips_guidelines_content="│ 1. Backup your settings first
│ 2. Download for your specific device
│ 3. Verify checksums before flashing"
    else
        title_block="╔══════════════════════╗
        🚀 *RTA-WRT FIRMWARE*
           🧪 *DEVELOPER BUILD*
╚══════════════════════╝"
        section_title="🧪 *Development Notes*"
        tips_guidelines_title="💡 *Testing Guidelines*"
        tips_guidelines_content="│ 1. Test WiFi stability over 24 hours
│ 2. Check CPU temperatures under load
│ 3. Verify all services function properly"
    fi

    cat <<EOF
$title_block

${TIME_EMOJI} Good ${TIME_OF_DAY}, $([[ "$message_type" = "main" ]] && echo "firmware enthusiasts!" || echo "beta testers!")

📱 *$(echo "$message_type" | sed 's/main/Release/; s/dev/Build/') Information*
┌─────────────────────
│ 🔹 *Version:* \`${SOURCE}:${VERSION}\`
│ 🔹 *Date:* ${CURRENT_DATE}
│ 🔹 *Time:* ${CURRENT_TIME}
└─────────────────────

$section_title (CHANGELOG)
┌─────────────────────
$changelog_content
└─────────────────────

$tips_guidelines_title
┌─────────────────────
$tips_guidelines_content
└─────────────────────

For Downloads, visit:
https://rtaserver-wrt.github.io/RTA-WRT/
EOF
}

# Function to send a photo with caption to Telegram
send_photo_to_telegram() {
    local photo_url="$1"
    local caption_text="$2"
    local max_retries=3
    local attempt=0
    local response
    local message_id=""

    echo "Sending main firmware announcement..."
    while [[ $attempt -lt $max_retries ]]; do
        attempt=$((attempt + 1))
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
            --data-urlencode "chat_id=${CHAT_ID}" \
            --data-urlencode "photo=${photo_url}" \
            --data-urlencode "caption=${caption_text}" \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "message_thread_id=${THREAD_ID}")

        if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
            message_id=$(echo "$response" | jq -r '.result.message_id')
            echo "Main message sent successfully with ID: $message_id"
            echo "$message_id" # Return message_id
            return 0
        else
            local error_code=$(echo "$response" | jq -r '.error_code')
            local error_desc=$(echo "$response" | jq -r '.description')
            echo "Attempt $attempt failed to send main message: Code $error_code - $error_desc"
            if [[ $attempt -lt $max_retries ]]; then
                local sleep_time=$((attempt * 3))
                echo "Retrying in $sleep_time seconds..."
                sleep "$sleep_time"
            else
                echo "::error::Failed to send main message after $max_retries attempts. Verify BOT_TOKEN, CHAT_ID, and message length."
                exit 1
            fi
        fi
    done
    return 1 # Should not reach here if successful
}

# Function to send a document (HTML file) to Telegram
send_document_to_telegram() {
    local file_path="$1"
    local en_caption_text="$2"
    local id_caption_text="$3"
    local reply_to_message_id="$4"

    echo -e "${YELLOW}[INFO] Sending ${file_path} to Telegram...${NC}"

    local caption="🌟 *RTA-WRT FIRMWARE UPDATE* 🌟

🇬🇧 *ENGLISH*
${en_caption_text}

🇮🇩 *BAHASA INDONESIA*
${id_caption_text}"

    local response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        -F "chat_id=${CHAT_ID}" \
        -F "document=@${file_path}" \
        -F "caption=${caption}" \
        -F "parse_mode=Markdown" \
        -F "reply_to_message_id=${reply_to_message_id}" \
        -F "message_thread_id=${THREAD_ID}")

    if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
        echo -e "${GREEN}[SUCCESS] File ${file_path} sent successfully${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] Failed to send file ${file_path}${NC}"
        echo -e "${RED}Response: ${response}${NC}"
        return 1
    fi
}

# --- Main Script Logic ---

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print banner
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                      ║${NC}"
echo -e "${BLUE}║  ${YELLOW}RTA-WRT FIRMWARE NOTIFICATION SYSTEM${BLUE}            ║${NC}"
echo -e "${BLUE}║  ${YELLOW}SISTEM NOTIFIKASI FIRMWARE RTA-WRT${BLUE}              ║${NC}"
echo -e "${BLUE}║                                                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"

# 1. Validate environment variables
validate_env_vars

# 2. Get theme image URL
image_url=$(get_theme_image_url "$SOURCE")

# 3. Get current time information
get_time_info

# 4. Extract changelog
extract_changelog

# 5. Generate main Telegram message caption
# We need to decide if the message needs truncation based on its length
# Telegram caption limit for sendPhoto is 1024 characters.
# We will generate the message once, check its length, and re-generate if needed.

# First attempt to generate message with current CHANGELOG (max 5 entries)
MAIN_MESSAGE=$(generate_telegram_caption "$FOR" "$CHANGELOG")

# Check message length and truncate changelog if necessary
if [[ ${#MAIN_MESSAGE} -gt 1024 ]]; then
    echo "Debug: Message length (${#MAIN_MESSAGE} chars) exceeds 1024 characters, truncating changelog further..."
    TRUNCATED_CHANGELOG=$(echo "$CHANGELOG_FULL" | head -n 3)
    if [[ $(echo "$CHANGELOG_FULL" | wc -l) -gt 3 ]]; then
        TRUNCATED_CHANGELOG+="
│ • And More..."
    fi
    MAIN_MESSAGE=$(generate_telegram_caption "$FOR" "$TRUNCATED_CHANGELOG")
    echo "Debug: Truncated message length: ${#MAIN_MESSAGE} characters"
else
    echo "Debug: Message length: ${#MAIN_MESSAGE} characters"
fi

# 6. Send the main photo message and capture its ID
MESSAGE_ID=$(send_photo_to_telegram "$image_url" "$MAIN_MESSAGE")
if [[ -z "$MESSAGE_ID" ]]; then
    echo -e "${RED}❌ Failed to get message ID for reply. Exiting.${NC}"
    exit 1
fi

echo "✅ Telegram message + HTML preview + data file sent!"