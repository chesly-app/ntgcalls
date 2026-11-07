# ntgcalls on iOS

ntgcalls builds for iOS: iPhone devices and the arm64 iPhone simulator. Third-party
components and their licences are in `THIRD_PARTY_NOTICES.md`. Every file the iOS build
changes is listed below, and the source changes carry an `iOS port` comment wherever a line
needs explaining.

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
- **No H.264, HEVC, AAC or MP3 decoders in FFmpeg.** ntgcalls decodes with FFmpeg only for
  group-call streams (`wrtc/src/interfaces/mtproto/*`, reached only from `GroupConnection`); a 1:1
  call never does, since its media goes through the external source. Without these decoders the
  binary is smaller and has less patent exposure. A group-call stream in one of these formats
  finds no decoder, which the streaming code already handles (`avcodec_find_decoder` returns
  null).
- **No desktop capture, no camera module, no `Boost::process`.** iOS has no desktop capture in
  WebRTC and cannot spawn processes; camera frames arrive through the external source.
- **Local network.** iOS asks the user before an app first sends to its local network. On iOS,
  ntgcalls does not offer LAN-only host candidates (RFC 1918, link-local, RFC 6598, unique-local
  IPv6) and does not try remote candidates on local addresses, on its own subnets, or named by
  any hostname it would have to resolve, mDNS included
  (`wrtc/include/wrtc/utils/local_network.hpp`). Calls between two devices on the same network
  then go through a public address or Telegram's reflectors. One case remains that only
  a libwebrtc change could close: a peer on the same IPv6 /64 that sends a check to this
  device's global IPv6 address gets an answer, so an app still needs
  `NSLocalNetworkUsageDescription`. The custom parameter `"network_allow_local_addresses": true`
  turns the filter off for one call, for a test on one machine. It is read once, when the
  connection is created.
- **The key fingerprint is not logged** on iOS (`ntgcalls/src/instances/p2p_call.cpp`).
- **Version.** `ntg_get_version()` returns `3.0.6+ios.<version.ios_port>.<commit>`; the framework's
  `CFBundleShortVersionString` is `3.0.6`, its `CFBundleVersion` the port revision, and
  `NTGCallsVersion` the full string.

## Files the iOS build changes

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
| new `IOS_PORT.md` | this file |

## Building

The workflow `.github/workflows/ios.yml` builds everything on a GitHub macOS runner
(Xcode 26.6) and keeps the outputs as draft release assets:

1. **Deps bundle** (`ios/scripts/build_deps.sh`), once per `version.ios_deps`: FFmpeg
   (`ios/scripts/build_ffmpeg.sh`, LGPL-2.1 configuration, fetched by the commit
   `version.ios_ffmpeg_commit`, which its tag must still name) and Boost.JSON (`ios/deps`), for
   both slices. pytgcalls publishes neither for iOS. Boost.JSON is compiled with the same clang and
   Chromium libc++ headers as ntgcalls (`ios/deps` declares `USE_LIBCXX` before `project()`, as
   the root `CMakeLists.txt` does), so its `std::` symbols are the WebRTC archive's
   (`std::__Cr`). The script fails if `libboost_json.a` references the SDK's `std::__1` at all,
   or never references `std::__Cr`. The bundle records the libc++, libc++abi and buildtools
   commits it was built against (`boost/libcxx.txt`, and `BUILD.txt`), and CMake stops if they
   differ from the WebRTC archive's: a WebRTC bump needs a `version.ios_deps` bump. Bundles
   before `version.ios_deps` 2 were built against the SDK's headers by mistake and must not be
   used.
2. **Slices** (`ios/scripts/build_slice.sh`, then `ios/scripts/package_framework.sh`). If the
   retagged simulator build fails, `ios/scripts/stub_slice.sh` builds a simulator slice whose
   every function answers "not built", and the report says so.
3. **Gate G0** (`ios/scripts/check_slice.sh`) on each slice: arm64 only, platform and minimum
   iOS, install name, system libraries only, only `_ntg_*` exported, no defined weak external,
   no ObjC class or category, no `AVAudioSession` or AVFoundation import, dSYM with matching
   UUID, no debug map in the shipped binary, the header identical to the release header, the
   version string, `Info.plist`, the privacy manifest, the software video factories linked
   without OpenH264, and no import that names the system libc++'s `std::__1`.
4. **xcframework**: `xcodebuild -create-xcframework` with both dSYMs, zipped for SwiftPM, with
   its SHA-256.
5. **Publish**: only a run that passed G0 on both slices, with the retagged (not the
   stub) simulator slice, replaces the draft `ios-v<version>-p<version.ios_port>`, whose target
   is the commit it was built from. That commit is first tagged `ios-build-<first 12 hex
   digits>`: `SOURCE.txt` in the framework names it as the corresponding source, so it must stay
   reachable whatever happens to this branch.

Only the release jobs, on Linux, hold a token that can write to the repository, and only in
their release steps. The build and test jobs read the repository only and pass their outputs on
as workflow artifacts. Every action is pinned by commit.

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
