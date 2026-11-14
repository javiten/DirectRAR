#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="${SDK_NAME:-iphoneos}"
SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
ARCH="${CURRENT_ARCH:-arm64}"
if [[ "$ARCH" == undefined_arch ]]; then ARCH=arm64; fi
BUILD="$ROOT/.build/$SDK-$ARCH"
mkdir -p "$BUILD" "$ROOT/Engine/include" "$ROOT/Engine/lib/$SDK-$ARCH"
if [[ ! -d "$ROOT/Vendor/libarchive-3.8.4" ]]; then
  tar -xf "$ROOT/Vendor/libarchive-3.8.4.tar.xz" -C "$ROOT/Vendor"
fi
SOURCE="$ROOT/Vendor/libarchive-3.8.4"
if [[ "$SDK" == iphonesimulator* ]]; then
  TARGET="$ARCH-apple-ios16.0-simulator"
else
  TARGET="$ARCH-apple-ios16.0"
fi
cd "$BUILD"
if [[ ! -f Makefile ]]; then
  CC="$(xcrun --sdk "$SDK" -f clang)" \
  CFLAGS="-target $TARGET -isysroot $SDK_PATH -O2" \
  LDFLAGS="-target $TARGET -isysroot $SDK_PATH" \
  "$SOURCE/configure" --host="$ARCH-apple-darwin" \
    --disable-shared --enable-static --without-openssl --without-xml2 \
    --without-expat --without-iconv --without-lzma --without-zstd \
    --without-lz4 --without-bz2lib --disable-bsdtar --disable-bsdcat \
    --disable-bsdcpio --disable-bsdunzip
fi
make -j"$(sysctl -n hw.ncpu)" libarchive.la
cp .libs/libarchive.a "$ROOT/Engine/lib/$SDK-$ARCH/"
cp "$SOURCE/libarchive/archive.h" "$SOURCE/libarchive/archive_entry.h" "$ROOT/Engine/include/"
