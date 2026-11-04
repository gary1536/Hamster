#!/usr/bin/env bash
# encoding: utf-8
# 用 macOS 版 librime 1.8.5（.deps，由 InputSchemaBuild.sh 下載）重新編譯嘸蝦米的 prism，
# 放進 HamsterKit 套件資源 Sources/Resources/PrebuiltPrism/。
#
# 為什麼需要：Frameworks/librime.xcframework（amorphobia/LibrimeKit v0.1.0，librime 1.8.5）
# 在 iOS 上建出的 *.prism.bin 是壞的（Darts double-array 單元寫成 8 bytes 間隔且只寫入前半），
# 查不到任何編碼。App 在把沙箱詞庫同步到 AppGroup 前，會用這份預編檔覆蓋
# （見 HamsterKit FileManager.repairBrokenPrisms）。
# 修改 boshiamy.dict.yaml 之後要重跑這支腳本，否則詞典 checksum 不符、不會套用。
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEPS="$ROOT/.deps/dist"
if [[ ! -x "$DEPS/bin/rime_deployer" ]]; then
  echo "找不到 $DEPS/bin/rime_deployer，請先執行 InputSchemaBuild.sh" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap "rm -rf \"$WORK\"" EXIT
mkdir -p "$WORK/user" "$WORK/shared"
unzip -q "$ROOT/Resources/SharedSupport/SharedSupport.zip" -d "$WORK/shared"
cp "$ROOT/Resources/InputSchemas/boshiamy/boshiamy.schema.yaml" \
   "$ROOT/Resources/InputSchemas/boshiamy/boshiamy.dict.yaml" "$WORK/user/"
printf "patch:\n  schema_list:\n    - schema: boshiamy\n" > "$WORK/user/default.custom.yaml"

DYLD_FALLBACK_LIBRARY_PATH="$DEPS/lib" \
  "$DEPS/bin/rime_deployer" --build "$WORK/user" "$WORK/shared" "$WORK/user/build" > /dev/null 2>&1

SRC="$WORK/user/build/boshiamy.prism.bin"
[[ -s "$SRC" ]] || { echo "沒有產生 boshiamy.prism.bin" >&2; exit 1; }
DST="$ROOT/Packages/HamsterKit/Sources/Resources/PrebuiltPrism"
mkdir -p "$DST"
cp "$SRC" "$DST/boshiamy.prism.bin"
echo "已更新 $DST/boshiamy.prism.bin（$(wc -c < "$DST/boshiamy.prism.bin" | tr -d " ") bytes）"
