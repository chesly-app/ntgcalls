set(BOOST_DIR ${DEPS_DIR}/boost)
set(BOOST_SRC ${BOOST_DIR}/src)
set(BOOST_GIT https://github.com/pytgcalls/boost)
set(BOOST_LIB_DIR ${BOOST_SRC}/lib)
set(BOOST_ATOMIC_LIB ${CMAKE_STATIC_LIBRARY_PREFIX}boost_atomic${CMAKE_STATIC_LIBRARY_SUFFIX})
set(BOOST_CONTEXT_LIB ${CMAKE_STATIC_LIBRARY_PREFIX}boost_context${CMAKE_STATIC_LIBRARY_SUFFIX})
set(BOOST_DATE_TIME_LIB ${CMAKE_STATIC_LIBRARY_PREFIX}boost_date_time${CMAKE_STATIC_LIBRARY_SUFFIX})
set(BOOST_FILESYSTEM_LIB ${CMAKE_STATIC_LIBRARY_PREFIX}boost_filesystem${CMAKE_STATIC_LIBRARY_SUFFIX})
set(BOOST_PROCESS_LIB ${CMAKE_STATIC_LIBRARY_PREFIX}boost_process${CMAKE_STATIC_LIBRARY_SUFFIX})
set(BOOST_JSON_LIB ${CMAKE_STATIC_LIBRARY_PREFIX}boost_json${CMAKE_STATIC_LIBRARY_SUFFIX})

if (ANDROID)
    set(BOOST_LIB_DIR ${BOOST_LIB_DIR}/${ANDROID_ABI})
endif ()

if (IOS)
    # iOS port: pytgcalls/boost publishes no iOS build. Boost.JSON, the only compiled part used
    # here, comes per slice from the iOS deps bundle (ios/deps), built against the same Chromium
    # libc++ headers as this library (std::__Cr); ios/scripts/build_deps.sh fails a bundle that
    # references the SDK's std::__1, and G0 check 14 fails a framework that imports it.
    # Boost::process stays off, as on Android: iOS cannot spawn.
    if (NOT NTG_IOS_DEPS)
        message(FATAL_ERROR "iOS needs -DNTG_IOS_DEPS=<dir> with boost/ and ffmpeg/ for this slice")
    endif ()
    set(BOOST_SRC ${NTG_IOS_DEPS}/boost)
    set(BOOST_LIB_DIR ${BOOST_SRC}/lib)
    if (NOT EXISTS ${BOOST_LIB_DIR}/${BOOST_JSON_LIB})
        message(FATAL_ERROR "Missing ${BOOST_LIB_DIR}/${BOOST_JSON_LIB}")
    endif ()
    # The bundle records the libc++ it was built against (ios/deps); it must be this archive's.
    if (NOT LIBCXX_COMMIT OR NOT EXISTS ${BOOST_SRC}/libcxx.txt)
        message(FATAL_ERROR "No libc++ record to check: LIBCXX_COMMIT='${LIBCXX_COMMIT}', ${BOOST_SRC}/libcxx.txt")
    endif ()
    file(READ ${BOOST_SRC}/libcxx.txt _NTG_BOOST_LIBCXX)
    set(_NTG_ARCHIVE_LIBCXX "LIBCXX_COMMIT=${LIBCXX_COMMIT}\nLIBCXX_ABI_COMMIT=${LIBCXX_ABI_COMMIT}\nBUILDTOOLS_COMMIT=${BUILDTOOLS_COMMIT}\n")
    if (NOT "${_NTG_BOOST_LIBCXX}" STREQUAL "${_NTG_ARCHIVE_LIBCXX}")
        message(FATAL_ERROR "The iOS deps bundle's Boost.JSON was built against another libc++ than the WebRTC archive's; bump version.ios_deps.\nbundle:\n${_NTG_BOOST_LIBCXX}archive:\n${_NTG_ARCHIVE_LIBCXX}")
    endif ()
    add_compile_definitions(BOOST_ALL_NO_LIB)
    message(STATUS "boost (iOS deps bundle) ${BOOST_SRC}")
    if (NOT TARGET Boost::json)
        add_library(Boost::json STATIC IMPORTED GLOBAL)
        set_target_properties(Boost::json PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${BOOST_SRC}/include"
            IMPORTED_LINK_INTERFACE_LANGUAGES CXX
            IMPORTED_LOCATION "${BOOST_LIB_DIR}/${BOOST_JSON_LIB}"
        )
    endif ()
    return()
elseif (LINUX_ARM64)
    set(PLATFORM linux)
    set(ARCHIVE_FORMAT .tar.gz)
    set(ARCH arm64)
elseif (LINUX_x86_64)
    set(PLATFORM linux)
    set(ARCHIVE_FORMAT .tar.gz)
    set(ARCH x86_64)
elseif (MACOS_ARM64)
    set(PLATFORM macos)
    set(ARCHIVE_FORMAT .tar.gz)
    set(ARCH arm64)
elseif (WINDOWS_x86_64)
    set(PLATFORM windows)
    set(ARCHIVE_FORMAT .zip)
    set(ARCH x86_64)
elseif (ANDROID)
    set(PLATFORM android)
    set(ARCHIVE_FORMAT .tar.gz)
    set(ARCH ${ANDROID_ABI})
else ()
    message(STATUS "Boost is not supported on ${CMAKE_SYSTEM_NAME} with ${CMAKE_HOST_SYSTEM_PROCESSOR}")
    return()
endif ()

add_compile_definitions(BOOST_ALL_NO_LIB)
GetProperty("version.boost" BOOST_VERSION)
message(STATUS "boost v${BOOST_VERSION}")

set(FILE_NAME boost.${PLATFORM})
if (NOT ANDROID)
    set(FILE_NAME ${FILE_NAME}-${ARCH})
endif ()
set(FILE_NAME ${FILE_NAME}${ARCHIVE_FORMAT})

DownloadProject(
    URL ${BOOST_GIT}/releases/download/v${BOOST_VERSION}/${FILE_NAME}
    DOWNLOAD_DIR ${BOOST_DIR}/download
    SOURCE_DIR ${BOOST_SRC}
)

if (NOT TARGET Boost::json)
    add_library(Boost::json STATIC IMPORTED GLOBAL)
    set_target_properties(Boost::json PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${BOOST_SRC}/include"
        IMPORTED_LINK_INTERFACE_LANGUAGES CXX
        IMPORTED_LOCATION "${BOOST_LIB_DIR}/${BOOST_JSON_LIB}"
    )
endif ()

if (NOT ANDROID)
    if (NOT TARGET Boost::atomic)
        add_library(Boost::atomic STATIC IMPORTED GLOBAL)
        set_target_properties(Boost::atomic PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${BOOST_SRC}/include"
            IMPORTED_LINK_INTERFACE_LANGUAGES CXX
            IMPORTED_LOCATION "${BOOST_LIB_DIR}/${BOOST_ATOMIC_LIB}"
        )
    endif ()

    if (NOT TARGET Boost::context)
        add_library(Boost::context STATIC IMPORTED GLOBAL)
        set_target_properties(Boost::context PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${BOOST_SRC}/include"
            IMPORTED_LINK_INTERFACE_LANGUAGES CXX
            IMPORTED_LOCATION "${BOOST_LIB_DIR}/${BOOST_CONTEXT_LIB}"
        )
    endif ()

    if (NOT TARGET Boost::date_time)
        add_library(Boost::date_time STATIC IMPORTED GLOBAL)
        set_target_properties(Boost::date_time PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${BOOST_SRC}/include"
            IMPORTED_LINK_INTERFACE_LANGUAGES CXX
            IMPORTED_LOCATION "${BOOST_LIB_DIR}/${BOOST_DATE_TIME_LIB}"
        )
    endif ()

    if (NOT TARGET Boost::filesystem)
        add_library(Boost::filesystem STATIC IMPORTED GLOBAL)
        set_target_properties(Boost::filesystem PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${BOOST_SRC}/include"
            IMPORTED_LINK_INTERFACE_LANGUAGES CXX
            IMPORTED_LOCATION "${BOOST_LIB_DIR}/${BOOST_FILESYSTEM_LIB}"
        )
        target_link_libraries(Boost::filesystem INTERFACE Boost::atomic)
    endif ()

    if(NOT TARGET Boost::process)
        add_library(Boost::process STATIC IMPORTED GLOBAL)
        set_target_properties(Boost::process PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${BOOST_SRC}/include"
            IMPORTED_LINK_INTERFACE_LANGUAGES CXX
            IMPORTED_LOCATION "${BOOST_LIB_DIR}/${BOOST_PROCESS_LIB}"
        )
        target_link_libraries(Boost::process INTERFACE Boost::atomic Boost::context Boost::date_time Boost::filesystem)
    endif ()

    add_compile_definitions(BOOST_ENABLED BOOST_ASIO_NO_DEPRECATED)
    set(BOOST_ENABLED TRUE)
endif ()
