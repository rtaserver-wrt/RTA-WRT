#!/bin/bash

. ./scripts/0-includes.sh.sh

cd "${WORK_DIR}" || exit 1

SOURCE="${1:-openwrt}"
TARGET="${2:-x86-64}"
VERSION="${3:-stable}"
TAG="$(firmware "TAG" "${VERSION}" "${SOURCE}")"