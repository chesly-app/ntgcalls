# iOS port (Chesly fork, 2026-11).
#
# Builds Boost.JSON for one iOS slice with the toolchain and libc++ headers this library uses
# itself: cmake/Toolchain.cmake, the libc++ commits FindWebRTC reads from the archive, and
# FindLibCXX. Its std:: symbols must be the archive's std::__Cr ones, not the SDK's std::__1:
# a std::string that Boost fills is read and freed by ntgcalls as the archive's std::string.
# ios/scripts/build_deps.sh configures it with the same flags as the library, plus
# -DNTG_IOS_DEPS_STAGE=ON, and fails if the library references std::__1 at all.
cmake_minimum_required(VERSION 3.27)

# Declared here as in the root CMakeLists.txt, and before project(): Toolchain.cmake reads it
# during project() to add -nostdinc++, and FindLibCXX reads it to fetch Chromium's libc++
# headers. Without it both do nothing and the SDK's own libc++ headers are used.
option(USE_LIBCXX "Use libc++" ON)

project(ntgcalls_ios_deps LANGUAGES C CXX)

get_filename_component(ROOT_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." REALPATH)
if (NOT IOS OR NOT NTG_IOS_DEPS_STAGE)
    message(FATAL_ERROR "Configure with cmake/Toolchain.cmake, -DCMAKE_SYSTEM_NAME=iOS and -DNTG_IOS_DEPS_STAGE=ON")
endif ()

include(${ROOT_DIR}/cmake/FindWebRTC.cmake)
include(${ROOT_DIR}/cmake/FindLibCXX.cmake)
if (NOT USE_LIBCXX OR NOT LIBCXX_COMMIT)
    message(FATAL_ERROR "Boost.JSON must be built against the archive's libc++ (USE_LIBCXX, LIBCXX_COMMIT)")
endif ()

# Boost's headers, from the pytgcalls/boost release the macOS build uses. Headers do not
# depend on the platform; only the compiled library does, and it is built below.
GetProperty("version.boost" BOOST_VERSION)
set(BOOST_DIR ${DEPS_DIR}/boost)
DownloadProject(
    URL https://github.com/pytgcalls/boost/releases/download/v${BOOST_VERSION}/boost.macos-arm64.tar.gz
    DOWNLOAD_DIR ${BOOST_DIR}/download
    SOURCE_DIR ${BOOST_DIR}/src
)

add_library(boost_json STATIC ${CMAKE_CURRENT_LIST_DIR}/boost_json.cpp)
target_include_directories(boost_json PRIVATE ${BOOST_DIR}/src/include)
target_compile_definitions(boost_json PRIVATE BOOST_ALL_NO_LIB)
set_target_properties(boost_json PROPERTIES
    CXX_STANDARD 20
    CXX_EXTENSIONS ON
    POSITION_INDEPENDENT_CODE ON
)
setup_platform_flags(boost_json OFF)

install(TARGETS boost_json ARCHIVE DESTINATION boost/lib)
install(DIRECTORY ${BOOST_DIR}/src/include/ DESTINATION boost/include)

# The libc++ this Boost.JSON is built against. FindBoost's iOS branch refuses a bundle whose
# commits differ from the WebRTC archive's: a bundle built against another libc++ still links,
# and nothing else would notice.
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/libcxx.txt
    "LIBCXX_COMMIT=${LIBCXX_COMMIT}\nLIBCXX_ABI_COMMIT=${LIBCXX_ABI_COMMIT}\nBUILDTOOLS_COMMIT=${BUILDTOOLS_COMMIT}\n")
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/libcxx.txt DESTINATION boost)
