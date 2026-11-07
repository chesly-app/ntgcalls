#!/usr/bin/env bash
# iOS port (Chesly fork, 2026-11).
#
# Builds FFmpeg's static libraries for one iOS slice: iphoneos or iphonesimulator, arm64.
# The configuration follows pytgcalls/ffmpeg's macOS build (same decoders, demuxers and parsers)
# with three changes for the iPhone:
# - no hardware decoders and no autodetected system libraries (VideoToolbox, AudioToolbox,
#   AVFoundation, Security): this library never decodes a group-call stream through them, and
#   each one would add a framework the iPhone build must not import;
# - no libopus encoder: nothing here encodes through FFmpeg, and WebRTC carries its own Opus;
# - zlib from the SDK is the only external library.
# FFmpeg is LGPL-2.1 here: neither --enable-gpl nor --enable-nonfree is used.
#
# Usage: build_ffmpeg.sh <iphoneos|iphonesimulator> <prefix> <ffmpeg version> <minimum iOS>
set -euo pipefail

sdk="$1"
prefix="$2"
version="$3"
min_ios="$4"

case "$sdk" in
    iphoneos) triple="arm64-apple-ios${min_ios}" ;;
    iphonesimulator) triple="arm64-apple-ios${min_ios}-simulator" ;;
    *) echo "unknown sdk $sdk" >&2; exit 1 ;;
esac

sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
cc="$(xcrun --sdk "$sdk" -f clang)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet --depth 1 --branch "n${version}" https://github.com/FFmpeg/FFmpeg.git "$work/src"

decoders=(
    h264 hevc mpeg4 msmpeg4v2 msmpeg4v3 opus aac aac_fixed aac_latm
    mp1 mp1float mp2 mp2float mp3 mp3adu mp3adufloat mp3float mp3on4 mp3on4float
    wavpack wmalossless wmapro wmav1 wmav2 wmavoice
    pcm_alaw pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_lxf pcm_mulaw
    pcm_s16be pcm_s16be_planar pcm_s16le pcm_s16le_planar
    pcm_s24be pcm_s24daud pcm_s24le pcm_s24le_planar
    pcm_s32be pcm_s32le pcm_s32le_planar pcm_s64be pcm_s64le pcm_s8 pcm_s8_planar
    pcm_u16be pcm_u16le pcm_u24be pcm_u24le pcm_u32be pcm_u32le pcm_u8
)
demuxers=(h264 hevc matroska m4v mov mp3 ogg wav aac)
parsers=(h264 hevc mpegaudio mpeg4video opus aac aac_latm)
muxers=(ogg opus mp4)

flags=()
for item in "${decoders[@]}"; do flags+=("--enable-decoder=$item"); done
for item in "${demuxers[@]}"; do flags+=("--enable-demuxer=$item"); done
for item in "${parsers[@]}"; do flags+=("--enable-parser=$item"); done
for item in "${muxers[@]}"; do flags+=("--enable-muxer=$item"); done

cflags="--target=${triple} -isysroot ${sysroot} -fvisibility=hidden -ffunction-sections -fdata-sections -O2 -g -fno-common"

cd "$work/src"
./configure \
    --prefix="$prefix" \
    --enable-cross-compile \
    --target-os=darwin \
    --arch=aarch64 \
    --cc="$cc" \
    --sysroot="$sysroot" \
    --extra-cflags="$cflags" \
    --extra-ldflags="--target=${triple} -isysroot ${sysroot}" \
    --enable-static --disable-shared \
    --disable-programs --disable-doc \
    --disable-autodetect --enable-zlib \
    --disable-network --disable-everything \
    --disable-avdevice --disable-avfilter --disable-swscale \
    --enable-runtime-cpudetect --enable-protocol=file \
    "${flags[@]}" \
    || { tail -n 80 ffbuild/config.log; exit 1; }

make -j"$(sysctl -n hw.ncpu)"
make install

for lib in avcodec avformat avutil swresample; do
    test -f "$prefix/lib/lib${lib}.a"
done
