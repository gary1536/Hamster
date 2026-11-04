#!/usr/bin/env bash
# encoding: utf-8
# 原 imfuxiao/LibrimeKit 已 404（2026-11 確認）。目前全部改用 amorphobia/LibrimeKit v0.1.0
# （librime 1.8.5）。曾試過 thomfang/LibrimeKit-iOS v0.2.2（librime 1.16.1），但它沒有匯出 C API，已棄用。
# 已知問題：這份 iOS librime 建出的 *.prism.bin 是壞的，App 改用預編 prism 覆蓋（見 PrebuiltPrismBuild.sh）。
# Hamster 的 pbxproj 已移除過期的 librime-sbxlm / boost_locale 引用。
set -e

OUTPUT="${PWD}/Frameworks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUTPUT"
rm -rf "$OUTPUT"/*.xcframework

# 注意：thomfang 版 librime 未匯出 C API（僅 2 個 _Rime* 符號），RimeKitObjC 需要 75 個，
# 必須用 amorphobia 版（librime 1.8.5，完整 C API）。
echo "==> 下載 amorphobia Frameworks.tgz (librime 1.8.5)"
curl -sL -o "$TMP/am.tgz" https://github.com/amorphobia/LibrimeKit/releases/download/v0.1.0/Frameworks.tgz
tar -xzf "$TMP/am.tgz" -C "$TMP"
cp -R "$TMP/Frameworks/"*.xcframework "$OUTPUT/"

echo "==> 完成：$(ls "$OUTPUT" | wc -l | tr -d ' ') 個 xcframework"
ls "$OUTPUT"
