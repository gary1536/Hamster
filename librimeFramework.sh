#!/usr/bin/env bash
# encoding: utf-8
# 原 imfuxiao/LibrimeKit 已 404（2026-11 確認）。目前全部改用 amorphobia/LibrimeKit v0.1.0
# （librime 1.8.5）。曾試過 thomfang/LibrimeKit-iOS v0.2.2（librime 1.16.1），但它沒有匯出 C API，已棄用。
# 注意：librime 與 OpenCC 各帶一份 darts-clone（id_type 分別是 4 與 8 bytes，名稱相同），連結進同一個 App
# 會發生 ODR 衝突，App 內建出的 *.prism.bin 是壞的。請改用 librimeLocalBuild.sh 從原始碼編譯
# （它把 librime 的 Darts 改名為 RimeDarts）。
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
