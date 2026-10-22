#!/usr/bin/env bash
# Builds liboqs (ML-KEM-768 only) for every Android ABI the app ships, the
# way android/app/src/main/jniLibs/*/liboqs.so were made.
#
# Source: https://github.com/open-quantum-safe/liboqs/archive/refs/tags/0.16.0.tar.gz
# SHA-256 of that archive: 162d5b510518ee5f285f82fa1f16402a885176e818bf1b1a4c3c91c9a2f01eae
# Checked with liboqs' own kat_kem against its recorded ML-KEM-768 hash.
set -euo pipefail

source="${1:?usage: oqs.sh <liboqs-0.16.0 source folder> <output folder>}"
here="${2:?usage: oqs.sh <liboqs-0.16.0 source folder> <output folder>}"
mkdir -p "$here/build"
sdk="$LOCALAPPDATA/Android/Sdk"
ndk="$sdk/ndk/28.2.13676358"
cmake="$sdk/cmake/3.22.1/bin/cmake.exe"
ninja="$sdk/cmake/3.22.1/bin/ninja.exe"

for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  build="$here/build/$abi"
  rm -rf "$build"
  "$cmake" -S "$source" -B "$build" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja" \
    -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON \
    -DOQS_USE_OPENSSL=OFF \
    -DOQS_BUILD_ONLY_LIB=ON \
    -DOQS_DIST_BUILD=ON \
    -DOQS_MINIMAL_BUILD="KEM_ml_kem_768" > "$build.log" 2>&1
  "$cmake" --build "$build" >> "$build.log" 2>&1
  echo "$abi: $(find "$build" -name 'liboqs.so' | head -1)"
done
