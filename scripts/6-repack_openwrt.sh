#!/bin/bash

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