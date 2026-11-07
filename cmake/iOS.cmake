# iOS port (Chesly fork, 2026-11): macOS.cmake's iPhone counterpart, for the C target only.
#
# - WEBRTC_IOS beside WEBRTC_MAC and WEBRTC_POSIX, as the archive was built: api/audio_options.h
#   and webrtc::AudioDeviceModule change shape under WEBRTC_IOS, so leaving it out would compile
#   against a layout the archive does not have.
# - No -ObjC. Media goes through the EXTERNAL path, so nothing needs an ObjC class from the
#   archive, and -ObjC would load all of them.
# - The shared library exports the C API (_ntg_*) and nothing else. WebRTC's C++ symbols, the weak
#   ones included, stay private to this image, so they cannot bind to another WebRTC copy in the
#   same app.
target_compile_definitions(${target_name} PUBLIC
    WEBRTC_POSIX
    WEBRTC_MAC
    WEBRTC_IOS
    _LIBCPP_DISABLE_AVAILABILITY
    _LIBCPP_DISABLE_VISIBILITY_ANNOTATIONS
    _LIBCXXABI_DISABLE_VISIBILITY_ANNOTATIONS
    _LIBCPP_ENABLE_NODISCARD
    _LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE
    NDEBUG
)
set_target_properties(${target_name} PROPERTIES CXX_VISIBILITY_PRESET hidden)

if (import_libraries)
    # AVFoundation, AVFAudio, AudioToolbox and UIKit are left out on purpose: a reference to any
    # of them means WebRTC's own iOS audio device was pulled in, and the link should say so.
    target_link_libraries(${target_name} PUBLIC
        "-framework Foundation"
        "-framework CoreFoundation"
        "-framework CoreGraphics"
        "-framework CoreMedia"
        "-framework CoreVideo"
        "-framework VideoToolbox"
        "-framework Security"
        "-framework SystemConfiguration"
        "-framework Network"
        "objc"
        "z"
    )
endif ()

get_target_property(_ntg_target_type ${target_name} TYPE)
if (_ntg_target_type STREQUAL "SHARED_LIBRARY")
    target_link_options(${target_name} PRIVATE
        "LINKER:-exported_symbols_list,${ROOT_DIR}/ios/ntgcalls.exp"
        "LINKER:-dead_strip"
        "LINKER:-dead_strip_dylibs"
        "LINKER:-headerpad_max_install_names"
    )
endif ()
