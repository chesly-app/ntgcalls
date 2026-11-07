#!/usr/bin/env bash
# iOS port (Chesly fork, 2026-11).
#
# Builds the iOS deps bundle: FFmpeg and Boost.JSON, for the device and the simulator slice.
# pytgcalls publishes neither for iOS. The bundle is built once per version.ios_deps revision
# and kept as a release asset, so a port round compiles only ntgcalls.
#
# Layout of the tarball:
#   iphoneos/ffmpeg/{include,lib}  iphoneos/boost/{include,lib}
#   iphonesimulator/...            (the same)
#   BUILD.txt                      versions, toolchain and checksums of the inputs
#
# Usage: build_deps.sh <output .tar.gz>
set -euo pipefail

out="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
root="$(cd "$(dirname "$0")/../.." && pwd)"
prop() { sed -n "s/^$1=//p" "$root/version.properties"; }

ffmpeg_version="$(prop version.ffmpeg)"
ffmpeg_commit="$(prop version.ios_ffmpeg_commit)"
boost_version="$(prop version.boost)"
min_ios="$(prop version.ios_min)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

for sdk in iphoneos iphonesimulator; do
    simulator=OFF
    [ "$sdk" = iphonesimulator ] && simulator=ON

    echo "::group::FFmpeg ${ffmpeg_version} for ${sdk}"
    "$root/ios/scripts/build_ffmpeg.sh" "$sdk" "$stage/$sdk/ffmpeg" "$ffmpeg_version" "$ffmpeg_commit" "$min_ios"
    echo "::endgroup::"

    echo "::group::Boost.JSON ${boost_version} for ${sdk}"
    build="$root/build/deps-$sdk"
    rm -rf "$build"
    cmake -S "$root/ios/deps" -B "$build" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_TOOLCHAIN_FILE="$root/cmake/Toolchain.cmake" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DNTG_IOS_SIMULATOR="$simulator" \
        -DNTG_IOS_DEPS_STAGE=ON \
        -DUSE_LIBCXX=ON \
        -DPython_EXECUTABLE="$(command -v python3)"
    cmake --build "$build"
    cmake --install "$build" --prefix "$stage/$sdk"
    test -s "$stage/$sdk/boost/libcxx.txt"
    echo "::endgroup::"

    # Every object in a slice's libraries must carry that slice's platform.
    for lib in ffmpeg/lib/libavcodec.a ffmpeg/lib/libavformat.a ffmpeg/lib/libavutil.a \
               ffmpeg/lib/libswresample.a boost/lib/libboost_json.a; do
        platforms="$("$root/ios/scripts/platforms.sh" "$stage/$sdk/$lib")"
        echo "$sdk/$lib: $platforms"
        [ "$platforms" = "$sdk" ] || { echo "$sdk/$lib holds objects for: $platforms" >&2; exit 1; }
    done

    # Boost.JSON must use the archive's libc++ (std::__Cr), never the SDK's (std::__1): both
    # link, and the two only agree on std::string's layout by chance. Matched anywhere in a name,
    # since std::__1 can sit in the middle of one (std::runtime_error(std::__1::string const&)).
    json="$stage/$sdk/boost/lib/libboost_json.a"
    json_symbols="$(nm -j "$json")"
    sdk_libcxx="$(grep -c 'St3__1' <<< "$json_symbols" || true)"
    archive_libcxx="$(grep -c 'St4__Cr' <<< "$json_symbols" || true)"
    echo "$sdk/boost/lib/libboost_json.a: $archive_libcxx std::__Cr references, $sdk_libcxx std::__1"
    if [ "$sdk_libcxx" -ne 0 ] || [ "$archive_libcxx" -eq 0 ]; then
        echo "$sdk/boost/lib/libboost_json.a is not built against the archive's libc++:" >&2
        grep 'St3__1' <<< "$json_symbols" | sort -u | head -20 >&2 || true
        exit 1
    fi
done

for name in webrtc.ios.tar.gz boost.macos-arm64.tar.gz; do
    found="$(find "$root/deps" -name "$name" -print -quit)"
    test -n "$found" || { echo "missing $name" >&2; exit 1; }
    expected="$(awk -v n="$name" '$2 == n {print $1}' "$root/ios/pins.sha256")"
    actual="$(shasum -a 256 "$found" | awk '{print $1}')"
    [ "$expected" = "$actual" ] || { echo "$name: $actual, pinned $expected" >&2; exit 1; }
done

{
    echo "ntgcalls iOS deps bundle, revision $(prop version.ios_deps)"
    echo "source: $(git -C "$root" rev-parse HEAD)"
    echo "ffmpeg: n${ffmpeg_version} at ${ffmpeg_commit} (github.com/FFmpeg/FFmpeg), ios/scripts/build_ffmpeg.sh"
    echo "boost: ${boost_version}, headers from pytgcalls/boost boost.macos-arm64.tar.gz, Boost.JSON built by ios/deps against the archive's libc++ (std::__Cr)"
    echo "boost built against:"
    sed 's/^/  /' "$stage/iphoneos/boost/libcxx.txt"
    echo "minimum iOS: ${min_ios}"
    echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
} > "$stage/BUILD.txt"

tar -czf "$out" -C "$stage" .
shasum -a 256 "$out"
