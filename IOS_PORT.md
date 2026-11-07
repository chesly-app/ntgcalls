# ntgcalls on iOS

This branch (`ios-port`) ports ntgcalls 3.0.6 to iOS: iPhone devices and the arm64 iPhone
simulator. It is a modified version of [pytgcalls/ntgcalls](https://github.com/pytgcalls/ntgcalls),
made by Chesly in November 2026 and distributed under the same licence, LGPL-3.0 (`LICENSE`).
Third-party components and their licences are in `THIRD_PARTY_NOTICES.md`. Every change is
marked in the source with an `iOS port` comment and listed below.

## What it produces

`ntgcalls.xcframework`: one dynamic framework per slice, module `ntgcalls`, with the C header
exactly as the upstream release ships it (`ntgcalls.h`, from `targets/c`). Each framework carries
its dSYM (`-debug-symbols`), an `Info.plist`, a privacy manifest and the licence notices.

| | Device | Simulator |
|---|---|---|
| Architecture | arm64 | arm64 |
| Minimum iOS | `version.ios_min` (14.0) | the same |
| WebRTC | `webrtc.ios.tar.gz` from pytgcalls/webrtc-build `m157.8103.4.0`, unmodified, pinned in `ios/pins.sha256` | the same objects, retagged as simulator objects |

## Design

- **Media goes through the `EXTERNAL` source.** The app owns the microphone, the speaker and the
  camera, and exchanges 10 ms PCM frames and I420 video frames with `ntg_send_external_frame`
  and the frames callback. ntgcalls never uses a platform audio device (its own
  `AudioDeviceModule` reports `kDummyAudio`), so it never touches `AVAudioSession`.
- **No ObjC, no AVFoundation.** `webrtc::CreateAudioDeviceModule` is defined to return null
  (`wrtc/src/interfaces/media/audio_device_module.cpp`). The voice engine asks for a platform
  device only when it was given none, and it always is. This keeps WebRTC's iOS audio device,
  `RTCAudioSession` and every other ObjC class out of the link. `-ObjC` is not used.
- **Only the C API is exported.** The library links with `-exported_symbols_list ios/ntgcalls.exp`
  (`_ntg_*`) and `-dead_strip`. None of WebRTC's C++ symbols, weak ones included, are visible
  outside the framework, so it can sit in one app beside another WebRTC build.
- **No OpenH264.** A source-built OpenH264 is not covered by Cisco's patent licence for its own
  binaries. VP8, VP9 and AV1 from WebRTC remain.
- **No desktop capture, no camera module, no `Boost::process`.** iOS has no desktop capture in
  WebRTC and cannot spawn processes; camera frames arrive through the external source.
- **Local network.** iOS asks the user before an app first sends to its local network. On iOS,
  ntgcalls does not offer LAN-only host candidates (RFC 1918, link-local, RFC 6598, unique-local
  IPv6) and does not try remote candidates on local addresses, on its own subnets, or named by
  mDNS (`wrtc/include/wrtc/utils/local_network.hpp`). Calls between two devices on the same
  network then go through a public address or Telegram's reflectors. One case remains that only
  a libwebrtc change could close: a peer on the same IPv6 /64 that sends a check to this
  device's global IPv6 address gets an answer, so an app still needs
  `NSLocalNetworkUsageDescription`. The custom parameter `"network_allow_local_addresses": true`
  turns the filter off for one call, which the same-machine test uses.
- **The key fingerprint is not logged** on iOS (`ntgcalls/src/instances/p2p_call.cpp`).
- **Version.** `ntg_get_version()` returns `3.0.6+ios.<version.ios_port>.<commit>`; the framework's
  `CFBundleShortVersionString` is `3.0.6`, its `CFBundleVersion` the port revision, and
  `NTGCallsVersion` the full string.

## Changes to upstream files

| File | Change |
|---|---|
| `cmake/PlatformUtils.cmake` | `IOS` platform (from `CMAKE_SYSTEM_NAME=iOS`), its flags file, static bundling with `libtool` |
| `cmake/Toolchain.cmake`, new `cmake/iOSToolchain.cmake` | iOS slice selection, SDK, target triple, Chromium clang and libc++ as on macOS |
| new `cmake/iOS.cmake` | `WEBRTC_IOS` with `WEBRTC_MAC` and `WEBRTC_POSIX`, system frameworks, export list, no `-ObjC` |
| `cmake/FindClang.cmake`, `cmake/FindLibCXX.cmake` | iOS takes the macOS host clang and the archive's libc++ headers |
| `cmake/FindWebRTC.cmake` | `webrtc.ios.tar.gz`; the simulator links a retagged copy |
| `cmake/FindBoost.cmake`, `cmake/FindFFmpeg.cmake` | iOS libraries come from the iOS deps bundle |
| `cmake/FindOpenH264.cmake`, `wrtc/CMakeLists.txt`, `wrtc/.../openh264/*`, `wrtc/.../cisco/*`, `wrtc/src/video_factory/video_factory_config.cpp` | no OpenH264 on iOS |
| `cmake/VersionUtil.cmake`, `version.properties` | iOS version string; `version.ios_min`, `version.ios_port`, `version.ios_deps` |
| `wrtc/include/wrtc/interfaces/media/audio_device_module.hpp`, `wrtc/src/interfaces/media/audio_device_module.cpp` | the two iOS-only `AudioDeviceModule` methods; the null `CreateAudioDeviceModule` |
| `wrtc/src/interfaces/native_connection.cpp`, new `wrtc/include/wrtc/utils/local_network.hpp`, `wrtc/src/utils/local_network.cpp` | local network filter |
| `ntgcalls/src/media/devices/media_device.cpp`, `desktop_capturer_module.*`, `camera_capturer_module.*` | no desktop capture or camera module on iOS |
| `ntgcalls/include/ntgcalls/utils/hardware_info.hpp`, `ntgcalls/src/utils/hardware_info.cpp` | iOS uses the macOS CPU accounting |
| `ntgcalls/src/instances/p2p_call.cpp` | no key fingerprint in the iOS log |
| new `ios/`, `.github/workflows/ios.yml` | build scripts, checks and the workflow |

## Building

The workflow `.github/workflows/ios.yml` builds everything on a GitHub macOS runner
(Xcode 26.6) and keeps the outputs as draft release assets:

1. **Deps bundle** (`ios/scripts/build_deps.sh`), once per `version.ios_deps`: FFmpeg
   (`ios/scripts/build_ffmpeg.sh`, LGPL-2.1 configuration) and Boost.JSON (`ios/deps`), for both
   slices. pytgcalls publishes neither for iOS. Boost.JSON is compiled with the same clang and
   libc++ headers as ntgcalls, so its `std::` symbols match the WebRTC archive's (`std::__Cr`).
2. **Slices** (`ios/scripts/build_slice.sh`, then `ios/scripts/package_framework.sh`). If the
   retagged simulator build fails, `ios/scripts/stub_slice.sh` builds a simulator slice whose
   every function answers "not built", and the report says so.
3. **Gate G0** (`ios/scripts/check_slice.sh`) on each slice: arm64 only, platform and minimum
   iOS, install name, system libraries only, only `_ntg_*` exported, no defined weak external,
   no ObjC class or category, no `AVAudioSession` or AVFoundation import, dSYM with matching
   UUID, no debug map in the shipped binary, the header identical to the release header, the
   version string, `Info.plist` and the privacy manifest.
4. **xcframework**: `xcodebuild -create-xcframework` with both dSYMs, zipped for SwiftPM, with
   its SHA-256.

To build by hand on a Mac with Xcode, CMake and Ninja:

```sh
ios/scripts/build_deps.sh /tmp/deps.tar.gz
mkdir -p /tmp/deps && tar -xzf /tmp/deps.tar.gz -C /tmp/deps
ios/scripts/build_slice.sh iphoneos /tmp/deps /tmp/out
ios/scripts/check_slice.sh iphoneos /tmp/out/iphoneos
```

## Replacing the framework (LGPL-3.0 section 4)

The library ships as its own dynamic framework, `ntgcalls.framework`, loaded by the app at
`@rpath/ntgcalls.framework/ntgcalls`. To run an app with a modified ntgcalls, build this source
with your changes as above, keep the C API, put your `ntgcalls.framework` in place of the app's
copy under `Frameworks/`, and sign the app again with your own identity.
