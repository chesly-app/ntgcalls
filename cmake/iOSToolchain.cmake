# iOS port (Chesly fork, 2026-11). Included by Toolchain.cmake when CMAKE_SYSTEM_NAME is iOS.
#
# One slice per configure: the iPhone itself (iphoneos), or the iPhone simulator on Apple silicon
# (-DNTG_IOS_SIMULATOR=ON). Both are arm64. The minimum OS comes from version.properties and is
# carried by the target triple, so CMake's own deployment-target flag stays unset.
option(NTG_IOS_SIMULATOR "Build the arm64 iPhone simulator slice instead of the device slice" OFF)
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES NTG_IOS_SIMULATOR)

GetProperty("version.ios_min" NTG_IOS_MIN)
if (NOT NTG_IOS_MIN)
    message(FATAL_ERROR "version.properties has no version.ios_min")
endif ()

if (NTG_IOS_SIMULATOR)
    set(NTG_IOS_SDK iphonesimulator)
    set(NTG_IOS_TRIPLE arm64-apple-ios${NTG_IOS_MIN}-simulator)
else ()
    set(NTG_IOS_SDK iphoneos)
    set(NTG_IOS_TRIPLE arm64-apple-ios${NTG_IOS_MIN})
endif ()

execute_process(
    COMMAND xcrun --sdk ${NTG_IOS_SDK} --show-sdk-path
    OUTPUT_VARIABLE NTG_IOS_SDK_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)

set(CMAKE_OSX_SYSROOT "${NTG_IOS_SDK_PATH}")
set(CMAKE_OSX_ARCHITECTURES "arm64")
set(CMAKE_OSX_DEPLOYMENT_TARGET "")
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION OFF)
# A test executable would need a signature to run anywhere, and nothing here runs one.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} --target=${NTG_IOS_TRIPLE}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} --target=${NTG_IOS_TRIPLE}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} --target=${NTG_IOS_TRIPLE}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} --target=${NTG_IOS_TRIPLE}")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} --target=${NTG_IOS_TRIPLE}")

message(STATUS "iOS slice: ${NTG_IOS_SDK} (${NTG_IOS_TRIPLE}), SDK ${NTG_IOS_SDK_PATH}")
