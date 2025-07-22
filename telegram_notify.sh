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

$section_title (see full changelog in firmware.html)
┌─────────────────────
$changelog_content
└─────────────────────

$tips_guidelines_title
┌─────────────────────
$tips_guidelines_content
└─────────────────────
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

# Function to parse combined_artifacts.txt into a button array
parse_buttons() {
    local button_array=()
    local file="combined_artifacts.txt"

    if [[ ! -f "$file" ]]; then
        echo "Warning: combined_artifacts.txt not found. No download buttons will be generated."
        return
    fi

    while IFS='|' read -r name url || [[ -n "$name" ]]; do
        name=$(echo "$name" | xargs)
        url=$(echo "$url" | xargs)

        # Skip empty lines or specific unwanted patterns
        if [[ -z "$name" || -z "$url" || "$name" == *"all-tunnelall-tunnel"* ]]; then
            continue
        fi

        if [[ "$url" =~ ^https?:// ]]; then
            button_array+=("$name" "$url")
        fi
    done < "$file"

    # Add "View Release" button if RELEASE_TAG is set
    if [[ -n "$RELEASE_TAG" ]]; then
        button_array+=("View Release" "https://github.com/rtaserver-wrt/RTA-WRT/releases/tag/$RELEASE_TAG")
    fi

    # Return the array elements separated by newline for easier processing outside
    printf "%s\n" "${button_array[@]}"
}

# Function to generate firmware.html
generate_firmware_html() {
    local firmware_js_escaped="$1"
    local changelog_js_escaped="$2"
    local source_val="$3"
    local version_val="$4"

    cat <<EOF > firmware.html
<!DOCTYPE html>
<html lang="en" class="scroll-smooth">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="theme-color" content="#0F172A" />
  <title>RTA-WRT Firmware Downloads</title>
  <!-- Tailwind CSS -->
  <script src="https://cdn.tailwindcss.com"></script>
  <!-- Font Awesome -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" integrity="sha512-iecdLmaskl7CVkqkXNQ/ZH/XLlvWZOJyj7Yy7tcenmpD1ypASozpmT/E0iPtmFIB46ZmdtAc9eNBvH0H/ZpiBw==" crossorigin="anonymous" referrerpolicy="no-referrer" />
  <!-- SweetAlert2 -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@sweetalert2/theme-dark@5/dark.css">
  <script src="https://cdn.jsdelivr.net/npm/sweetalert2@11/dist/sweetalert2.min.js"></script>
  <!-- AOS Animation Library -->
  <link href="https://cdn.jsdelivr.net/npm/aos@2.3.4/dist/aos.css" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/aos@2.3.4/dist/aos.js"></script>
  <!-- Alpine.js -->
  <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.12.0/dist/cdn.min.js"></script>
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            primary: {
              50: '#eef7ff', 100: '#d9edff', 200: '#bce0ff', 300: '#8bcbff', 400: '#53adff',
              500: '#2a90ff', 600: '#1272f5', 700: '#0d5bdd', 800: '#104ab4', 900: '#12408f', 950: '#0c2554',
            },
            secondary: {
              50: '#f5f7fa', 100: '#ebeef3', 200: '#d2dae7', 300: '#a7b8d2', 400: '#7896bc', 
              500: '#5679a8', 600: '#40618c', 700: '#344f72', 800: '#2e4460', 900: '#293a51', 950: '#1a2433',
            },
          },
          fontFamily: {
            sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'],
          },
          animation: {
            'fade-in': 'fadeIn 0.5s ease-out forwards',
            'fade-in-up': 'fadeInUp 0.6s ease-out forwards',
            'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
            'spin-slow': 'spin 2s linear infinite',
            'bounce-slow': 'bounce 2s infinite',
            'float': 'float 3s ease-in-out infinite',
          },
          keyframes: {
            fadeIn: { '0%': { opacity: '0' }, '100%': { opacity: '1' } },
            fadeInUp: { '0%': { opacity: '0', transform: 'translateY(10px)' }, '100%': { opacity: '1', transform: 'translateY(0)' } },
            float: {
              '0%, 100%': { transform: 'translateY(0)' },
              '50%': { transform: 'translateY(-10px)' },
            },
          },
          boxShadow: {
            'glow': '0 0 15px rgba(42, 144, 255, 0.5)',
            'glow-lg': '0 0 25px rgba(42, 144, 255, 0.6)',
            'card': '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
            'card-hover': '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
          }
        }
      }
    }
  </script>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
    
    .bg-gradient-mesh {
      background-image: 
        radial-gradient(circle at 15% 50%, rgba(42, 144, 255, 0.1) 0%, transparent 25%),
        radial-gradient(circle at 85% 30%, rgba(16, 74, 180, 0.1) 0%, transparent 25%),
        linear-gradient(135deg, #0c2554 0%, #104ab4 100%);
      background-attachment: fixed;
    }
    
    .text-gradient {
      background: linear-gradient(90deg, #2a90ff 0%, #1272f5 100%);
      -webkit-background-clip: text;
      background-clip: text;
      color: transparent;
    }
    
    .card-shine {
      position: relative;
      overflow: hidden;
    }
    
    .card-shine::before {
      content: "";
      position: absolute;
      top: 0;
      left: -75%;
      z-index: 2;
      display: block;
      width: 50%;
      height: 100%;
      background: linear-gradient(to right, rgba(255,255,255,0) 0%, rgba(255,255,255,0.1) 100%);
      transform: skewX(-25deg);
      transition: all 0.75s;
    }
    
    .card-shine:hover::before {
      animation: shine 1.5s;
    }
    
    @keyframes shine {
      100% { left: 125%; }
    }
    
    .nav-item {
      position: relative;
    }
    
    .nav-item::after {
      content: '';
      position: absolute;
      width: 0;
      height: 2px;
      bottom: -2px;
      left: 0;
      background-color: #2a90ff;
      transition: width 0.3s ease;
    }
    
    .nav-item:hover::after, .nav-item.active::after {
      width: 100%;
    }
    
    .tooltip-trigger .tooltip {
      visibility: hidden;
      opacity: 0;
      transition: opacity 0.3s;
    }
    
    .tooltip-trigger:hover .tooltip {
      visibility: visible;
      opacity: 1;
    }
    
    .firmware-count {
      position: relative;
      overflow: hidden;
    }
    
    .firmware-count .bar {
      position: absolute;
      bottom: 0;
      left: 0;
      height: 2px;
      width: 100%;
      background-color: #2a90ff;
      transform: scaleX(0);
      transform-origin: left;
      transition: transform 0.5s ease;
    }
    
    .firmware-count:hover .bar {
      transform: scaleX(1);
    }
    
    ::-webkit-scrollbar {
      width: 8px;
      height: 8px;
    }
    
    ::-webkit-scrollbar-track {
      background: #1a2433;
    }
    
    ::-webkit-scrollbar-thumb {
      background: #344f72;
      border-radius: 4px;
    }
    
    ::-webkit-scrollbar-thumb:hover {
      background: #40618c;
    }
    
    .search-animate {
      transition: all 0.3s ease;
    }
    
    .search-animate:focus {
      transform: scale(1.01);
    }

    .swal-html-container {
      max-height: 70vh;
      overflow-y: auto;
    }
  </style>
</head>
<body class="antialiased" x-data="firmwareApp()">
  <div class="min-h-screen bg-gradient-mesh text-slate-100 font-sans pb-8">
    <!-- Navbar -->
    <nav class="backdrop-blur-md bg-slate-900/80 sticky top-0 z-50 shadow-md border-b border-slate-800/80" x-data="{ isMobileMenuOpen: false }">
      <div class="container mx-auto px-4 py-3 flex flex-wrap items-center justify-between">
        <div class="flex items-center space-x-2">
          <div class="h-10 w-10 rounded-lg bg-primary-600 flex items-center justify-center shadow-glow">
            <i class="fa-solid fa-wifi text-white text-lg"></i>
          </div>
          <div>
            <a href="#" class="text-xl font-bold text-white">RTA-WRT</a>
            <div class="text-xs text-slate-400">Open Source Router Firmware</div>
          </div>
        </div>
        
        <div class="hidden md:flex items-center space-x-6">
          <a href="#" class="nav-item text-white flex items-center space-x-1 active py-1">
            <i class="fa-solid fa-download text-primary-400"></i>
            <span>Firmware</span>
          </a>
          <a href="#" class="nav-item text-slate-300 hover:text-white flex items-center space-x-1 py-1">
            <i class="fa-solid fa-book"></i>
            <span>Documentation</span>
          </a>
          <a href="https://github.com/rtaserver-wrt/RTA-WRT" class="nav-item text-slate-300 hover:text-white flex items-center space-x-1 py-1">
            <i class="fa-solid fa-code-branch"></i>
            <span>GitHub</span>
          </a>
          <a href="https://t.me/backup_rtawrt" class="nav-item text-slate-300 hover:text-white flex items-center space-x-1 py-1">
            <i class="fa-solid fa-circle-question"></i>
            <span>Support</span>
          </a>
        </div>
        
        <button 
          class="md:hidden text-white focus:outline-none" 
          @click="isMobileMenuOpen = !isMobileMenuOpen"
          :aria-expanded="isMobileMenuOpen"
          aria-label="Toggle mobile menu">
          <i :class="isMobileMenuOpen ? 'fa-solid fa-times' : 'fa-solid fa-bars'" class="text-xl"></i>
        </button>
      </div>
      
      <!-- Mobile Menu -->
      <div 
        class="md:hidden bg-slate-900 border-b border-slate-800"
        x-show="isMobileMenuOpen"
        x-transition:enter="transition ease-out duration-300"
        x-transition:enter-start="opacity-0 transform -translate-y-4"
        x-transition:enter-end="opacity-100 transform translate-y-0"
        x-transition:leave="transition ease-in duration-200"
        x-transition:leave-start="opacity-100 transform translate-y-0"
        x-transition:leave-end="opacity-0 transform -translate-y-4">
        <div class="container mx-auto px-4 py-3">
          <div class="flex flex-col space-y-3">
            <a href="#" class="text-white py-2 px-3 rounded-lg bg-primary-800/30 flex items-center space-x-2">
              <i class="fa-solid fa-download text-primary-400"></i>
              <span>Firmware</span>
            </a>
            <a href="#" class="text-slate-300 hover:text-white py-2 px-3 rounded-lg hover:bg-slate-800/50 flex items-center space-x-2">
              <i class="fa-solid fa-book"></i>
              <span>Documentation</span>
            </a>
            <a href="https://github.com/rtaserver-wrt/RTA-WRT" class="text-slate-300 hover:text-white py-2 px-3 rounded-lg hover:bg-slate-800/50 flex items-center space-x-2">
              <i class="fa-solid fa-code-branch"></i>
              <span>GitHub</span>
            </a>
            <a href="https://t.me/backup_rtawrt" class="text-slate-300 hover:text-white py-2 px-3 rounded-lg hover:bg-slate-800/50 flex items-center space-x-2">
              <i class="fa-solid fa-circle-question"></i>
              <span>Support</span>
            </a>
          </div>
        </div>
      </div>
    </nav>

    <!-- Hero Section -->
    <div class="container mx-auto px-4 pt-12 pb-8" data-aos="fade-up" data-aos-duration="800">
      <div class="text-center mb-12">
        <h1 class="text-4xl md:text-5xl lg:text-6xl font-bold mb-3 text-gradient tracking-tight">
          RTA-WRT Firmware
        </h1>
        <p class="text-slate-300 text-lg md:text-xl max-w-2xl mx-auto">
          Powerful, customizable open-source firmware for your network devices
        </p>
        <div class="mt-6 flex justify-center space-x-4">
          <span class="inline-flex items-center px-3 py-1 rounded-full bg-primary-900/50 text-primary-200 border border-primary-700/50 text-sm">
            <i class="fa-solid fa-code-commit mr-1.5"></i> Latest Version: ${version_val}
          </span>
          <span class="inline-flex items-center px-3 py-1 rounded-full bg-secondary-900/50 text-secondary-200 border border-secondary-700/50 text-sm">
            <i class="fa-solid fa-calendar-check mr-1.5"></i> Released: ${CURRENT_DATE}
          </span>
        </div>
      </div>

      <!-- Changelog Card -->
      <div class="max-w-3xl mx-auto mb-12" data-aos="fade-up" data-aos-delay="200">
        <div class="relative bg-slate-800/80 backdrop-blur-sm rounded-xl border border-slate-700 p-6 shadow-lg overflow-hidden group">
          <div class="absolute inset-0 bg-gradient-to-r from-primary-600/5 to-primary-800/10 opacity-0 group-hover:opacity-100 transition-opacity duration-500"></div>
          
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-2xl font-semibold text-slate-100">Changelog <span class="text-primary-400">${source_val}:${version_val}</span></h2>
          </div>
          
          <ul class="text-slate-300 space-y-3">
            $(echo "$changelog_js_escaped" | sed 's/│ • /<li class="flex items-start"><i class="fa-solid fa-circle-check text-primary-500 mt-1 mr-2"><\/i><span>/g; s/$/<\/span><\/li>/g')
          </ul>
          
          <div class="absolute top-0 right-0 w-32 h-32 transform translate-x-16 -translate-y-16 bg-primary-500/10 rounded-full blur-xl"></div>
          <div class="absolute bottom-0 left-0 w-32 h-32 transform -translate-x-16 translate-y-16 bg-primary-600/10 rounded-full blur-xl"></div>
        </div>
      </div>

      <!-- Search Section -->
      <div class="max-w-3xl mx-auto" data-aos="fade-up" data-aos-delay="300">
        <div class="relative mb-6">
          <div class="absolute inset-y-0 left-0 flex items-center pl-4 pointer-events-none">
            <i class="fa-solid fa-magnifying-glass text-slate-400"></i>
          </div>
          <input
            id="search"
            type="text"
            class="w-full p-4 pl-11 rounded-xl border-2 border-slate-700/80 bg-slate-800/60 text-slate-100 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/30 transition-all backdrop-blur-md search-animate"
            placeholder="Search firmware by device name..."
            autocomplete="off"
            x-model="searchQuery"
            @input="filterFirmware()"
          />
          <div class="absolute inset-y-0 right-0 flex items-center pr-3" x-show="searchQuery" x-cloak>
            <button 
              @click="clearSearch()" 
              class="p-1.5 rounded-full hover:bg-slate-700/50 text-slate-400 hover:text-slate-200 transition-colors">
              <i class="fa-solid fa-times"></i>
            </button>
          </div>
        </div>

        <!-- Filters and Info -->
        <div class="flex flex-col md:flex-row justify-between items-start md:items-center mb-6 text-sm text-slate-400 py-2">
          <div class="firmware-count mb-3 md:mb-0 px-1.5 py-1 relative">
            <span x-text="countDisplay"></span>
            <div class="bar"></div>
          </div>
          
          <div class="flex flex-wrap gap-3">
            <div class="flex items-center tooltip-trigger">
              <i class="fa-regular fa-clock mr-2 text-primary-400"></i>
              <span>Updated: ${CURRENT_DATE}</span>
              <div class="tooltip absolute -top-10 left-1/2 transform -translate-x-1/2 px-3 py-1.5 bg-slate-900 text-xs rounded-lg whitespace-nowrap">
                Last firmware repository update
              </div>
            </div>
            
            <button 
              @click="showDeviceGuide()" 
              class="ml-2 flex items-center text-primary-400 hover:text-primary-300 transition-colors">
              <i class="fa-solid fa-circle-info mr-1.5"></i>
              <span>Device guide</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Loader -->
      <div 
        id="loader" 
        class="flex flex-col items-center justify-center my-12"
        x-show="loading"
        x-transition:enter="transition ease-out duration-300"
        x-transition:enter-start="opacity-0 transform scale-90"
        x-transition:enter-end="opacity-100 transform scale-100"
        x-transition:leave="transition ease-in duration-300"
        x-transition:leave-start="opacity-100 transform scale-100"
        x-transition:leave-end="opacity-0 transform scale-90">
        <div class="w-12 h-12 border-4 border-primary-200/20 border-t-primary-500 rounded-full animate-spin-slow mb-4"></div>
        <p class="text-slate-400 animate-pulse">Loading firmware data...</p>
      </div>

      <!-- Empty State -->
      <div 
        x-show="!loading && filteredFirmware.length === 0" 
        class="max-w-3xl mx-auto py-12 px-6 border-2 border-dashed border-slate-700 rounded-2xl text-center"
        x-transition:enter="transition ease-out duration-300"
        x-transition:enter-start="opacity-0 transform -translate-y-4"
        x-transition:enter-end="opacity-100 transform translate-y-0">
        <i class="fa-regular fa-face-frown text-4xl text-slate-500 mb-4 animate-bounce-slow"></i>
        <h3 class="text-xl font-semibold text-slate-300 mb-2">No firmware found</h3>
        <p class="text-slate-400 mb-4">Try adjusting your search query or check back later</p>
        <button 
          @click="clearSearch()" 
          class="inline-flex items-center px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-700 text-white transition-colors">
          <i class="fa-solid fa-xmark mr-2"></i>
          Clear Search
        </button>
      </div>

      <!-- Firmware Grid -->
      <div 
        id="firmware-list" 
        class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
        x-show="!loading && filteredFirmware.length > 0"
        x-transition:enter="transition-opacity duration-500"
        x-transition:enter-start="opacity-0"
        x-transition:enter-end="opacity-100">
        <!-- Firmware Card Template -->
        <template x-for="(item, index) in filteredFirmware" :key="item.id">
          <div 
            class="card-shine bg-slate-800/80 backdrop-blur-sm rounded-xl border border-slate-700 p-6 shadow-lg transition-all duration-300 hover:shadow-xl hover:border-slate-600 hover:bg-slate-800"
            :data-aos="'fade-up'"
            :data-aos-delay="100 + (index % 9) * 50"
            :data-aos-offset="-100">
            <div class="mb-5 relative">
              <div class="absolute -right-2 -top-2 w-16 h-16 bg-primary-500/5 rounded-full blur-xl"></div>
              
              <div class="flex items-start justify-between mb-3">
                <div class="flex items-start">
                  <div class="h-9 w-9 rounded-lg bg-primary-500/10 flex items-center justify-center mr-3">
                    <i class="fa-solid fa-microchip text-primary-400"></i>
                  </div>
                  <h2 class="text-lg font-semibold text-slate-100 leading-tight">
                    <span x-text="formatDeviceName(item.name)"></span>
                  </h2>
                </div>
                <div class="tooltip-trigger" @mouseenter="showTooltip(item)" @mouseleave="hideTooltip()">
                  <button class="h-7 w-7 flex items-center justify-center rounded-full bg-slate-700/50 hover:bg-primary-600/20 text-slate-400 hover:text-primary-400 transition-colors">
                    <i class="fa-solid fa-info text-xs"></i>
                  </button>
                </div>
              </div>
              
              <div class="flex items-center mb-3">
                <span class="text-xs px-2.5 py-1 rounded-full bg-primary-900/40 text-primary-300 border border-primary-800/50 font-medium" x-text="getDeviceType(item.name)"></span>
                <span class="text-xs px-2.5 py-1 rounded-full bg-slate-700/40 text-slate-300 border border-slate-700/50 font-medium ml-2" x-text="getKernelVersion(item.name)"></span>
              </div>
              
              <p class="text-slate-400 text-sm">
                Official firmware image optimized for <span class="text-slate-300" x-text="getModelName(item.name)"></span>. Includes RTA-WRT extensions.
              </p>
            </div>
            
            <div class="flex space-x-2">
              <button 
                @click="downloadFirmware(item)" 
                class="flex-grow flex items-center justify-center bg-primary-600 hover:bg-primary-700 text-white font-medium py-2.5 px-4 rounded-lg transition-all duration-300 hover:shadow-glow group">
                <i class="fa-solid fa-download mr-2 group-hover:animate-bounce"></i>
                <span>Download</span>
              </button>
              
              <button 
                @click="copyLink(item)"
                class="h-10 w-10 flex items-center justify-center rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 hover:text-white transition-colors">
                <i class="fa-solid fa-link text-sm"></i>
              </button>
            </div>
          </div>
        </template>
      </div>
    </div>

    <!-- Footer -->
    <footer class="mt-20 py-8 border-t border-slate-800/50 bg-slate-900/40 backdrop-blur-sm">
      <div class="container mx-auto px-4">
        <div class="flex flex-col md:flex-row justify-between items-center">
          <div class="flex items-center space-x-2 mb-4 md:mb-0">
            <div class="h-8 w-8 rounded-lg bg-primary-700 flex items-center justify-center">
              <i class="fa-solid fa-wifi text-white text-sm"></i>
            </div>
            <div class="text-white font-bold">RTA-WRT</div>
          </div>
          
          <div class="flex space-x-6 mb-6 md:mb-0">
            <a href="https://github.com/rtaserver-wrt" class="text-slate-400 hover:text-white transition-colors">
              <i class="fa-brands fa-github text-lg"></i>
            </a>
            <a href="https://t.me/rtawrt" class="text-slate-400 hover:text-white transition-colors">
              <i class="fa-brands fa-telegram text-lg"></i>
            </a>
            <a href="https://t.me/backup_rtawrt" class="text-slate-400 hover:text-white transition-colors">
              <i class="fa-solid fa-circle-question text-lg"></i>
            </a>
          </div>
          
          <div class="text-slate-500 text-sm">
            <p>RTA-WRT Firmware Portal © <span id="current-year"></span></p>
          </div>
        </div>
      </div>
    </footer>
  </div>

  <script>
    // Initialize AOS
    document.addEventListener('DOMContentLoaded', () => {
      AOS.init({
        duration: 800,
        once: true,
        offset: 50
      });
      
      document.getElementById('current-year').textContent = new Date().getFullYear().toString();
    });
    
    function firmwareApp() {
      return {
        firmwareData: [],
        filteredFirmware: [],
        searchQuery: '',
        loading: true,
        countDisplay: 'Loading firmware...',
        
        init() {
          // Parse firmware data
          const firmwareDataRaw = \`
${firmware_js_escaped}
          \`;

          this.firmwareData = firmwareDataRaw.trim().split('\n')
            .filter(line => line.trim().length > 0)
            .map(line => {
              const [name, url] = line.trim().split('|');
              return { 
                name: name.trim(), 
                url: url.trim(),
                id: Math.random().toString(36).substring(2, 10)
              };
            });
          
          // Simulate loading and initialize filtered data
          setTimeout(() => {
            this.loading = false;
            this.filteredFirmware = [...this.firmwareData];
            this.updateCountDisplay();
          }, 800);
        },
        
        filterFirmware() {
          const query = this.searchQuery.toLowerCase();
          this.filteredFirmware = this.firmwareData.filter(item => 
            item.name.toLowerCase().includes(query)
          );
          this.updateCountDisplay();
        },
        
        updateCountDisplay() {
          const count = this.filteredFirmware.length;
          this.countDisplay = \`Showing \${count} firmware \${count === 1 ? 'image' : 'images'}\`;
        },
        
        clearSearch() {
          this.searchQuery = '';
          this.filteredFirmware = [...this.firmwareData];
          this.updateCountDisplay();
          document.getElementById('search').focus();
        },
        
        formatDeviceName(name) {
          return name
            .replace(/-k[0-9]+\.[0-9]+\.[0-9]+-/, '-')
            .replace(/_/g, ' ')
            .replace(/--/g, '-');
        },
        
        getDeviceType(name) {
          if (name.includes('X86_64')) return 'x86_64';
          if (name.includes('Amlogic')) return 'Amlogic';
          if (name.includes('Rockchip')) return 'Rockchip';
          if (name.includes('Allwinner')) return 'Allwinner';
          if (name.includes('Broadcom')) return 'Broadcom';
          return 'Generic';
        },
        
        getKernelVersion(name) {
          const kernelMatch = name.match(/k([0-9]+\.[0-9]+\.[0-9]+)/);
          return kernelMatch ? \`Kernel \${kernelMatch[1]}\` : 'Latest Kernel';
        },
        
        getModelName(name) {
          if (name.includes('OrangePi')) return 'Orange Pi Series devices';
          if (name.includes('Amlogic')) return 'Amlogic Series devices';
          if (name.includes('X86_64')) {
            if (name.includes('EFI')) return 'x86_64 EFI systems';
            if (name.includes('Rootfs')) return 'x86_64 Rootfs';
            return 'x86_64 systems';
          }
          return 'compatible devices';
        },
        
        showTooltip(item) {
          const deviceType = this.getDeviceType(item.name);
          const kernelVersion = this.getKernelVersion(item.name);
          const features = item.name.includes('all-tunnel') ? 'Includes tunneling support' : 'Standard version';
          
          Swal.fire({
            title: this.formatDeviceName(item.name),
            html: \`
              <div class="text-left">
                <p class="mb-2"><span class="font-semibold">Device Type:</span> \${deviceType}</p>
                <p class="mb-2"><span class="font-semibold">Kernel:</span> \${kernelVersion}</p>
                <p class="mb-2"><span class="font-semibold">Features:</span> \${features}</p>
                <p class="mt-4 text-sm">This firmware is fully compatible with the RTA-WRT ecosystem and includes all standard packages.</p>
              </div>
            \`,
            icon: 'info',
            showCloseButton: true,
            showConfirmButton: false,
            customClass: {
              popup: 'swal-wide',
            }
          });
        },
        
        hideTooltip() {
          // For future enhancements with custom tooltips
        },
        
        downloadFirmware(item) {
          Swal.fire({
            title: 'Starting Download',
            text: \`Preparing \${this.formatDeviceName(item.name)} firmware for download...\`,
            icon: 'info',
            timer: 1500,
            timerProgressBar: true,
            showConfirmButton: false,
            willClose: () => {
              // Simulate download by opening in new tab
              window.open(item.url, '_blank');
              
              // Show success message
              setTimeout(() => {
                Swal.fire({
                  title: 'Download Started',
                  text: 'Your download has started in a new tab. If you have any issues, try the direct link option.',
                  icon: 'success',
                  showConfirmButton: true,
                  confirmButtonText: 'Got it'
                });
              }, 500);
            }
          });
        },
        
        copyLink(item) {
          // Create a temporary input
          const tempInput = document.createElement('input');
          tempInput.value = item.url;
          document.body.appendChild(tempInput);
          tempInput.select();
          document.execCommand('copy');
          document.body.removeChild(tempInput);
          
          // Show toast notification
          Swal.fire({
            toast: true,
            position: 'bottom-end',
            icon: 'success',
            title: 'Download link copied to clipboard!',
            showConfirmButton: false,
            timer: 2000,
            timerProgressBar: true,
            showClass: {
              popup: 'animate__animated animate__fadeInUp animate__faster'
            },
            hideClass: {
              popup: 'animate__animated animate__fadeOutDown animate__faster'
            }
          });
        },
        
        showDeviceGuide() {
          Swal.fire({
            title: 'Device Compatibility Guide',
            html: \`
              <div class="text-left">
                <h3 class="text-lg font-semibold mb-2 text-primary-400">Understanding Firmware Names</h3>
                <p class="mb-4 text-sm">Our firmware naming follows this pattern: <strong>Platform_Model-KernelVersion-Features</strong></p>
                
                <h3 class="text-lg font-semibold mb-2 text-primary-400">Platform Types</h3>
                <ul class="space-y-1 mb-4 text-sm">
                  <li>• <strong>X86_64</strong>: For standard PC/server hardware</li>
                  <li>• <strong>Amlogic</strong>: For TV boxes and devices with Amlogic SoCs</li>
                  <li>• <strong>Rockchip</strong>: For devices based on Rockchip processors</li>
                  <li>• <strong>Allwinner</strong>: For devices with Allwinner SoCs</li>
                  <li>• <strong>Broadcom</strong>: For Broadcom-based devices</li>
                  <li>• <strong>Generic</strong>: For various other platforms</li>
                </ul>
                
                <h3 class="text-lg font-semibold mb-2 text-primary-400">Special Variants</h3>
                <ul class="space-y-1 mb-4 text-sm">
                  <li>• <strong>EFI</strong>: For UEFI boot systems</li>
                  <li>• <strong>Combined</strong>: Contains both kernel and rootfs in one image</li>
                  <li>• <strong>Rootfs</strong>: Root filesystem only (for advanced users)</li>
                </ul>
                
                <h3 class="text-lg font-semibold mb-2 text-primary-400">Feature Tags</h3>
                <ul class="space-y-1 text-sm">
                  <li>• <strong>all-tunnel</strong>: Includes all tunneling protocols and VPN support</li>
                </ul>
              </div>
            \`,
            showCloseButton: true,
            showConfirmButton: false,
            width: '600px',
            customClass: {
              container: 'swal-wide'
            }
          });
        }
      }
    }
  </script>
</body>
</html>
EOF
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

# 7. Parse buttons for HTML file
ALL_BUTTONS=($(parse_buttons))
# Escape button data for JavaScript in HTML
FIRMWARE_JS_ESCAPED=""
for (( i=0; i<${#ALL_BUTTONS[@]}; i+=2 )); do
    name_esc=$(echo "${ALL_BUTTONS[i]}" | sed 's/"/\\"/g; s/|/\\|/g')
    url_esc=$(echo "${ALL_BUTTONS[i+1]}" | sed 's/"/\\"/g; s/|/\\|/g')
    FIRMWARE_JS_ESCAPED+="${name_esc}|${url_esc}\n"
done

# Escape full changelog for JavaScript in HTML
CHANGELOG_JS_ESCAPED=$(echo "$CHANGELOG" | sed 's/"/\\"/g; s/|/\\|/g; s/\r//g') # Remove carriage returns
echo $CHANGELOG_JS_ESCAPED

# 8. Generate firmware.html
generate_firmware_html "$FIRMWARE_JS_ESCAPED" "$CHANGELOG_JS_ESCAPED" "$SOURCE" "$VERSION"

# 9. Send firmware.html as a document
echo -e "${BLUE}[PROCESS] Sending firmware.html to Telegram...${NC}"

# English caption for HTML file
HTML_EN_CAPTION="Click the document above to open the full firmware download page in your browser.
This page contains all available firmware images and a complete changelog.
If the document does not display correctly, please download and open it manually."

# Indonesian caption for HTML file
HTML_ID_CAPTION="Klik dokumen di atas untuk membuka halaman unduhan firmware lengkap di browser Anda.
Halaman ini berisi semua gambar firmware yang tersedia dan changelog lengkap.
Jika dokumen tidak ditampilkan dengan benar, harap unduh dan buka secara manual."

if send_document_to_telegram "firmware.html" "$HTML_EN_CAPTION" "$HTML_ID_CAPTION" "$MESSAGE_ID"; then
    echo -e "\n${GREEN}✅ All notifications sent successfully!${NC}"
else
    echo -e "\n${RED}❌ Error occurred during notification process${NC}"
    exit 1
fi

echo "✅ Telegram message + HTML preview + data file sent!"