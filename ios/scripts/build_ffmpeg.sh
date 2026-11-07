#!/usr/bin/env bash
# iOS port.
#
# Builds FFmpeg's static libraries for one iOS slice: iphoneos or iphonesimulator, arm64.
# The configuration follows pytgcalls/ffmpeg's macOS build with four changes for the iPhone:
# - no H.264, HEVC, AAC or MP3 decoders, and none of their parsers or raw demuxers: ntgcalls
#   decodes with FFmpeg only for group-call streams (wrtc/src/interfaces/mtproto/*, reached only
#   from GroupConnection), never in a 1:1 call, whose media goes through the external source.
#   fewer decoders make a smaller binary with less patent exposure;
# - no hardware decoders and no autodetected system libraries (VideoToolbox, AudioToolbox,
#   AVFoundation, Security): this library never decodes a group-call stream through them, and
#   each one would add a framework the iPhone build must not import;
# - no libopus encoder: nothing here encodes through FFmpeg, and WebRTC carries its own Opus;
# - zlib from the SDK is the only external library.
# FFmpeg is LGPL-2.1 here: neither --enable-gpl nor --enable-nonfree is used.
#
# FFmpeg is fetched by commit, not by its tag, and the tag must still name that commit.
#
# Usage: build_ffmpeg.sh <iphoneos|iphonesimulator> <prefix> <ffmpeg version> <commit> <minimum iOS>
set -euo pipefail

sdk="$1"
prefix="$2"
version="$3"
commit="$4"
min_ios="$5"
ffmpeg_git=https://github.com/FFmpeg/FFmpeg.git

case "$sdk" in
    iphoneos) triple="arm64-apple-ios${min_ios}" ;;
    iphonesimulator) triple="arm64-apple-ios${min_ios}-simulator" ;;
    *) echo "unknown sdk $sdk" >&2; exit 1 ;;
esac

sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
cc="$(xcrun --sdk "$sdk" -f clang)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

tagged="$(git ls-remote "$ffmpeg_git" "refs/tags/n${version}^{}" | awk '{print $1}')"
[ "$tagged" = "$commit" ] || { echo "FFmpeg n${version} is ${tagged:-missing}, pinned ${commit}" >&2; exit 1; }
git init --quiet "$work/src"
git -C "$work/src" fetch --quiet --depth 1 "$ffmpeg_git" "$commit"
git -C "$work/src" checkout --quiet FETCH_HEAD
[ "$(git -C "$work/src" rev-parse HEAD)" = "$commit" ]

decoders=(
    mpeg4 msmpeg4v2 msmpeg4v3 opus
    mp1 mp1float mp2 mp2float
    wavpack wmalossless wmapro wmav1 wmav2 wmavoice
    pcm_alaw pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_lxf pcm_mulaw
    pcm_s16be pcm_s16be_planar pcm_s16le pcm_s16le_planar
    pcm_s24be pcm_s24daud pcm_s24le pcm_s24le_planar
    pcm_s32be pcm_s32le pcm_s32le_planar pcm_s64be pcm_s64le pcm_s8 pcm_s8_planar
    pcm_u16be pcm_u16le pcm_u24be pcm_u24le pcm_u32be pcm_u32le pcm_u8
)
demuxers=(matroska m4v mov mp3 ogg wav)
parsers=(mpegaudio mpeg4video opus)
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
# None of the dropped decoders may come back through another option's dependencies. The names
# are read first: grep -q in a pipe would end nm early, and pipefail would read that as no match.
codec_symbols="$(nm -j -U "$prefix/lib/libavcodec.a" 2>/dev/null)"
for codec in h264 hevc aac aac_fixed aac_latm mp3 mp3float mp3adu mp3adufloat mp3on4 mp3on4float; do
    if grep -qx "_ff_${codec}_decoder" <<< "$codec_symbols"; then
        echo "libavcodec.a still has the ${codec} decoder" >&2
        exit 1
    fi
done
