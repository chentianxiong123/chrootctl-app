#!/usr/bin/env bash
# ChrootCtl 构建脚本 — 用系统 gradle 9.3.1 (零下载), AGP 9.0.0
set -euo pipefail
cd "$(dirname "$0")"

export ANDROID_HOME=/usr/local/android-sdk
echo "== 构建 ChrootCtl APK (debug) =="
gradle assembleDebug --no-daemon 2>&1 | tail -20

echo ""
echo "== 产物 =="
ls -la app/build/outputs/apk/debug/*.apk 2>/dev/null || echo "未生成 APK"