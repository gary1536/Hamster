#!/usr/bin/env bash
# encoding: utf-8
#
# 從原始碼編譯 iOS 用的 librime 1.8.5（合併 librime-lua）與所有相依套件，
# 產生 Frameworks/ 下的 10 個 xcframework（ios-arm64 + ios-arm64-simulator）。
#
# 為什麼不用 librimeFramework.sh 下載的預編版：
#   在 App 裡建出的 *.prism.bin 是壞的（Darts double-array 單元以 8 bytes 間隔寫入且只寫進前半），
#   所有方案都查不到編碼。根因是 librime 與 OpenCC 各帶一份 darts-clone，id_type 大小不同但名稱
#   相同，連結進同一個 App 時發生 ODR 衝突。這裡編 librime 時把它的 Darts 改名為 RimeDarts。
#
# Lua 的合併方式沿用 LibrimeKit（amorphobia/LibrimeKit 55e1c3c 的 librimeBuild.sh）：
#   librime-lua 原始碼放進 src/rime/lua，Lua 5.4 原始碼放進 src/rime/lua/lib/lua，
#   並以 scripts/librime/ 下的 core_module.cc、src-CMakeLists.txt 取代 librime 的對應檔。
#
# 需求：Xcode、Homebrew 的 cmake。中間檔放在 .librime-build/（已加入 .gitignore）。
# 用法：./librimeLocalBuild.sh            # 全部編譯並更新 Frameworks/
#       PLATFORMS="sim" ./librimeLocalBuild.sh   # 只編模擬器（不更新 Frameworks/）
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$ROOT/.librime-build}"
OUT="$ROOT/Frameworks"
MIN_IOS="15.0"
JOBS="$(sysctl -n hw.ncpu)"
PLATFORMS="${PLATFORMS:-os sim}"

LIBRIME_REPO="https://github.com/rime/librime.git"
LIBRIME_COMMIT="08dd95f5d9282346f0d4a3e8fc6b20811dc3d063"   # 1.8.5
LUA_PLUGIN_REPO="https://github.com/imfuxiao/librime-lua.git"
LUA_PLUGIN_COMMIT="af329e3"                                  # 2023-04-13，LibrimeKit 當時的 main
LUA_SRC_REPO="https://github.com/hchunhui/librime-lua.git"
LUA_SRC_COMMIT="a7b4c0af50e4a209f794beb1c86e33f2d9888c2e"   # thirdparty 分支，Lua 5.4.4
BOOST_VERSION="1.78.0"
BOOST_SHA256="8681f175d4bdb26c52222665793eef08490d7758529330f98d3b29dd0735bccc"
BOOST_DIR="boost_${BOOST_VERSION//./_}"

command -v cmake > /dev/null || { echo "需要 cmake（brew install cmake）" >&2; exit 1; }
mkdir -p "$WORK/logs"
cd "$WORK"
log() { echo "==> $*"; }

# ---------- 原始碼 ----------
fetch_commit() { # repo dir commit [branch]
  local repo="$1" dir="$2" commit="$3" branch="${4:-}"
  if [[ ! -d "$dir/.git" ]]; then
    if [[ -n "$branch" ]]; then git clone -q -b "$branch" "$repo" "$dir"; else git clone -q "$repo" "$dir"; fi
  fi
  git -C "$dir" checkout -q -f "$commit"
}

log "原始碼：librime $LIBRIME_COMMIT"
fetch_commit "$LIBRIME_REPO" librime "$LIBRIME_COMMIT"
git -C librime clean -qfdx src
git -C librime submodule update -q --init --depth 1
log "原始碼：librime-lua $LUA_PLUGIN_COMMIT、Lua $LUA_SRC_COMMIT"
fetch_commit "$LUA_PLUGIN_REPO" librime-lua "$LUA_PLUGIN_COMMIT"
fetch_commit "$LUA_SRC_REPO" lua-thirdparty "$LUA_SRC_COMMIT" thirdparty

log "合併 Lua 到 librime"
rm -rf librime/src/rime/lua
mkdir -p librime/src/rime/lua/lib/lua
cp -R librime-lua/src/* librime/src/rime/lua/
cp lua-thirdparty/lua5.4/*.c lua-thirdparty/lua5.4/*.h librime/src/rime/lua/lib/lua/
rm -f librime/src/rime/lua/lib/lua/lua.c librime/src/rime/lua/lib/lua/luac.c librime/src/rime/lua/lib/lua/onelua.c
# iOS 沒有 system()；Lua 5.4.4 尚無 LUA_USE_IOS，比照 5.4.6+ 的做法改成「沒有 shell」
sed -i '' 's|^  stat = system(cmd);$|  stat = (cmd == NULL) ? 0 : -1;  /* iOS: system() unavailable */|' \
  librime/src/rime/lua/lib/lua/loslib.c
grep -q 'iOS: system() unavailable' librime/src/rime/lua/lib/lua/loslib.c
cp "$ROOT/scripts/librime/core_module.cc" librime/src/rime/core_module.cc
cp "$ROOT/scripts/librime/src-CMakeLists.txt" librime/src/CMakeLists.txt

if [[ ! -d "$BOOST_DIR" ]]; then
  log "下載 boost $BOOST_VERSION"
  curl -sfL -o boost.tar.bz2 "https://archives.boost.io/release/$BOOST_VERSION/source/$BOOST_DIR.tar.bz2"
  echo "$BOOST_SHA256  boost.tar.bz2" | shasum -a 256 -c - > /dev/null
  tar xjf boost.tar.bz2 && rm boost.tar.bz2
fi
if [[ ! -x "$BOOST_DIR/b2" ]]; then
  (cd "$BOOST_DIR" && ./bootstrap.sh --with-toolset=clang > "$WORK/logs/boost-bootstrap.log" 2>&1)
fi

# ---------- 逐平台編譯 ----------
build_platform() {
  local plat="$1" sdk triple
  case "$plat" in
    os)  sdk=iphoneos;        triple="arm64-apple-ios$MIN_IOS" ;;
    sim) sdk=iphonesimulator; triple="arm64-apple-ios$MIN_IOS-simulator" ;;
  esac
  local P="$WORK/$plat" SDKPATH
  SDKPATH="$(xcrun --sdk $sdk --show-sdk-path)"
  local F="-target $triple -isysroot $SDKPATH"
  local L="$WORK/logs/$plat"
  mkdir -p "$P" "$L"

  log "[$plat] boost"
  if [[ ! -f "$P/boost/lib/libboost_filesystem.a" ]]; then
    printf 'using clang : ios%s : xcrun clang++ : <cxxflags>"%s -std=c++17" <cflags>"%s" <linkflags>"%s" <archiver>ar <ranlib>ranlib ;\n' \
      "$plat" "$F" "$F" "$F" > "$WORK/$BOOST_DIR/user-config-$plat.jam"
    (cd "$WORK/$BOOST_DIR" && ./b2 --user-config="user-config-$plat.jam" toolset="clang-ios$plat" \
      target-os=iphone architecture=arm address-model=64 link=static variant=release threading=multi \
      --with-filesystem --with-regex --with-system --build-dir="$WORK/boost-build-$plat" \
      --prefix="$P/boost" -j"$JOBS" install) > "$L/boost.log" 2>&1
  fi

  local CM=(
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_SYSROOT="$sdk"
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS"
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DCMAKE_INSTALL_PREFIX="$P"
    -DCMAKE_PREFIX_PATH="$P;$P/boost"
    -DCMAKE_FIND_ROOT_PATH="$P;$P/boost"
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DCMAKE_MACOSX_BUNDLE=OFF
  )
  local D="$WORK/librime/deps"

  log "[$plat] glog"
  cmake -S "$D/glog" -B "$D/glog/build-$plat" "${CM[@]}" -DBUILD_TESTING=OFF -DWITH_GFLAGS=OFF -DWITH_UNWIND=OFF > "$L/glog.log" 2>&1
  cmake --build "$D/glog/build-$plat" --target install -j"$JOBS" >> "$L/glog.log" 2>&1

  log "[$plat] leveldb"
  cmake -S "$D/leveldb" -B "$D/leveldb/build-$plat" "${CM[@]}" -DLEVELDB_BUILD_BENCHMARKS=OFF -DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_INSTALL=ON > "$L/leveldb.log" 2>&1
  cmake --build "$D/leveldb/build-$plat" --target install -j"$JOBS" >> "$L/leveldb.log" 2>&1

  log "[$plat] marisa"
  cmake -S "$D" -B "$D/marisa-trie/build-$plat" "${CM[@]}" > "$L/marisa.log" 2>&1
  cmake --build "$D/marisa-trie/build-$plat" --target install -j"$JOBS" >> "$L/marisa.log" 2>&1

  log "[$plat] yaml-cpp"
  cmake -S "$D/yaml-cpp" -B "$D/yaml-cpp/build-$plat" "${CM[@]}" -DYAML_CPP_BUILD_CONTRIB=OFF -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF > "$L/yaml-cpp.log" 2>&1
  cmake --build "$D/yaml-cpp/build-$plat" --target install -j"$JOBS" >> "$L/yaml-cpp.log" 2>&1

  log "[$plat] opencc（只編函式庫）"
  cmake -S "$D/opencc" -B "$D/opencc/build-$plat" "${CM[@]}" -DBUILD_DOCUMENTATION=OFF -DENABLE_GTEST=OFF -DENABLE_BENCHMARK=OFF > "$L/opencc.log" 2>&1
  cmake --build "$D/opencc/build-$plat" --target libopencc -j"$JOBS" >> "$L/opencc.log" 2>&1
  mkdir -p "$P/include/opencc" "$P/lib"
  cp "$D/opencc/build-$plat/src/libopencc.a" "$P/lib/"
  cp "$D/opencc/src/"*.hpp "$D/opencc/src/"*.h "$P/include/opencc/" 2> /dev/null || true
  cp "$D/opencc/build-$plat/src/opencc_config.h" "$P/include/opencc/" 2> /dev/null || true

  log "[$plat] librime（含 Lua）"
  # librime-lua 用 <lua.h>／<lualib.h> 引入 Lua 標頭，要把 Lua 原始碼目錄加進 include 路徑
  local LUA_DEFS="-DLUA_COMPAT_5_3 -DLUA_USE_IOS -I$WORK/librime/src/rime/lua/lib/lua"
  # 重要：OpenCC 附的 darts-clone 0.32 用 `typedef size_t id_type`（8 bytes），librime 的用
  # `unsigned int`（4 bytes），namespace 與類別名稱完全相同。兩者連結進同一個 App 時（Hamster 的
  # OpenCCBridge 會拉進 OpenCC 的 DartsDict），inline 模板產生 ODR 衝突，librime 建 prism 時用到
  # OpenCC 的 8-byte 版本，產生「單元 8 bytes 間隔、只寫前半」的壞 prism。
  # 把 librime 的 Darts 改名成 RimeDarts 以避開衝突（OpenCC 標頭只有 DartsDict，不受影響）。
  local RIME_CXX_DEFS="$LUA_DEFS -DDarts=RimeDarts"
  rm -rf "$WORK/librime/build-$plat"
  cmake -S "$WORK/librime" -B "$WORK/librime/build-$plat" "${CM[@]}" \
    -DCMAKE_C_FLAGS="$LUA_DEFS" -DCMAKE_CXX_FLAGS="$RIME_CXX_DEFS" \
    -DBOOST_ROOT="$P/boost" -DBoost_USE_STATIC_LIBS=ON \
    -DBUILD_STATIC=ON -DBUILD_TEST=OFF -DBUILD_MERGED_PLUGINS=ON \
    -DENABLE_EXTERNAL_PLUGINS=OFF -DENABLE_LOGGING=ON > "$L/librime.log" 2>&1
  cmake --build "$WORK/librime/build-$plat" --target rime-static -j"$JOBS" >> "$L/librime.log" 2>&1
  cp "$WORK/librime/build-$plat/lib/librime.a" "$P/lib/librime.a"
}

for plat in $PLATFORMS; do
  build_platform "$plat"
done

# ---------- 打包 xcframework ----------
if [[ "$PLATFORMS" != *os* || "$PLATFORMS" != *sim* ]]; then
  log "只編了 $PLATFORMS，不更新 Frameworks/"
  exit 0
fi

log "打包 xcframework"
BACKUP="$WORK/Frameworks-backup-amorphobia"
if [[ ! -d "$BACKUP" && -d "$OUT" ]]; then
  cp -R "$OUT" "$BACKUP"
  log "原本的 Frameworks 已備份到 $BACKUP"
fi
mkdir -p "$OUT" "$WORK/headers"
cp "$WORK/librime/src/rime_api.h" "$WORK/librime/src/rime_levers_api.h" "$WORK/headers/"

make_xcf() { # name os.a sim.a [headers]
  local name="$1" os="$2" sim="$3" hdr="${4:-}"
  rm -rf "$OUT/$name.xcframework"
  if [[ -n "$hdr" ]]; then
    xcodebuild -create-xcframework -library "$os" -headers "$hdr" -library "$sim" -headers "$hdr" -output "$OUT/$name.xcframework" > /dev/null
  else
    xcodebuild -create-xcframework -library "$os" -library "$sim" -output "$OUT/$name.xcframework" > /dev/null
  fi
}

make_xcf librime "$WORK/os/lib/librime.a" "$WORK/sim/lib/librime.a" "$WORK/headers"
for b in atomic filesystem regex system; do
  make_xcf "boost_$b" "$WORK/os/boost/lib/libboost_$b.a" "$WORK/sim/boost/lib/libboost_$b.a"
done
for l in libglog libleveldb libmarisa libopencc libyaml-cpp; do
  make_xcf "$l" "$WORK/os/lib/$l.a" "$WORK/sim/lib/$l.a"
done

log "完成"
ls "$OUT"
