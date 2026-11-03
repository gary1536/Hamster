#!/usr/bin/env bash
# encoding: utf-8
# 原 imfuxiao/LibrimeKit 已 404（2026-11 確認）。改用兩個可用來源合併：
#   - thomfang/LibrimeKit-iOS v0.2.2：librime 1.16.1 全套（缺 boost_atomic）
#   - amorphobia/LibrimeKit v0.1.0：補 boost_atomic（含 ios-arm64 切片）
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
