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

echo "==> 下載 thomfang Frameworks.tgz (librime 1.16.1)"
curl -sL -o "$TMP/thom.tgz" https://github.com/thomfang/LibrimeKit-iOS/releases/download/v0.2.2/Frameworks.tgz
tar -xzf "$TMP/thom.tgz" -C "$TMP"
for f in "$TMP"/*.xcframework; do
  case "$(basename "$f")" in
    boost_thread.xcframework) continue ;;  # Hamster 不需要
  esac
  cp -R "$f" "$OUTPUT/"
done

echo "==> 下載 amorphobia Frameworks.tgz（補 boost_atomic）"
curl -sL -o "$TMP/am.tgz" https://github.com/amorphobia/LibrimeKit/releases/download/v0.1.0/Frameworks.tgz
tar -xzf "$TMP/am.tgz" -C "$TMP"
cp -R "$TMP/Frameworks/boost_atomic.xcframework" "$OUTPUT/"

echo "==> 完成：$(ls "$OUTPUT" | wc -l | tr -d ' ') 個 xcframework"
ls "$OUTPUT"
