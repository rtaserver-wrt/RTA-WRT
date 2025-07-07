#!/bin/bash
# diy-part1.sh - Kustomisasi feeds dan tambahan repository

# Menambahkan feed tambahan
echo "src-git passwall https://github.com/xiaorouji/openwrt-passwall" >> feeds.conf.default
echo "src-git openclash https://github.com/vernesong/OpenClash" >> feeds.conf.default
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages" >> feeds.conf.default