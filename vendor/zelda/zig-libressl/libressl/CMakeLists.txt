if(MSVC)
	cmake_minimum_required (VERSION 3.16.4)
	cmake_policy(SET CMP0091 NEW)
else()
	cmake_minimum_required (VERSION 3.0)
endif()

project (LibreSSL C ASM)

include(CheckFunctionExists)
include(CheckSymbolExists)
include(CheckLibraryExists)
include(CheckIncludeFiles)
include(CheckTypeSize)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}" ${CMAKE_MODULE_PATH})
include(cmake_export_symbol)
include(GNUInstallDirs)

enable_testing()

file(READ ${CMAKE_CURRENT_SOURCE_DIR}/ssl/VERSION SSL_VERSION)
string(STRIP ${SSL_VERSION} SSL_VERSION)
string(REPLACE ":" "." SSL_VERSION ${SSL_VERSION})
string(REGEX REPLACE "\\..*" "" SSL_MAJOR_VERSION ${SSL_VERSION})

file(READ ${CMAKE_CURRENT_SOURCE_DIR}/crypto/VERSION CRYPTO_VERSION)
string(STRIP ${CRYPTO_VERSION} CRYPTO_VERSION)
string(REPLACE ":" "." CRYPTO_VERSION ${CRYPTO_VERSION})
string(REGEX REPLACE "\\..*" "" CRYPTO_MAJOR_VERSION ${CRYPTO_VERSION})

file(READ ${CMAKE_CURRENT_SOURCE_DIR}/tls/VERSION TLS_VERSION)
string(STRIP ${TLS_VERSION} TLS_VERSION)
string(REPLACE ":" "." TLS_VERSION ${TLS_VERSION})
string(REGEX REPLACE "\\..*" "" TLS_MAJOR_VERSION ${TLS_VERSION})

option(LIBRESSL_SKIP_INSTALL "Skip installation" ${LIBRESSL_SKIP_INSTALL})
option(LIBRESSL_APPS "Build apps" ON)
option(LIBRESSL_TESTS "Build tests" ON)
option(ENABLE_ASM "Enable assembly" ON)
option(ENABLE_EXTRATESTS "Enable extra tests that may be unreliable on some platforms" OFF)
option(ENABLE_NC "Enable installing TLS-enabled nc(1)" OFF)
set(OPENSSLDIR ${OPENSSLDIR} CACHE PATH "Set the default openssl directory" FORCE)

option(USE_STATIC_MSVC_RUNTIMES "Use /MT instead of /MD in MSVC" OFF)
if(USE_STATIC_MSVC_RUNTIMES)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

if(NOT LIBRESSL_SKIP_INSTALL)
	set( ENABLE_LIBRESSL_INSTALL ON )
endif(NOT LIBRESSL_SKIP_INSTALL)


set(BUILD_NC true)

if(CMAKE_SYSTEM_NAME MATCHES "Darwin")
	add_definitions(-fno-common)
endif()

if(CMAKE_SYSTEM_NAME MATCHES "OpenBSD")
	add_definitions(-DHAVE_ATTRIBUTE__BOUNDED__)
	add_definitions(-DHAVE_ATTRIBUTE__DEAD__)
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Linux")
	add_definitions(-D_DEFAULT_SOURCE)
	add_definitions(-D_BSD_SOURCE)
	add_definitions(-D_POSIX_SOURCE)
	add_definitions(-D_GNU_SOURCE)
	set(PLATFORM_LIBS ${PLATFORM_LIBS} pthread)
endif()

if(WIN32 OR (CMAKE_SYSTEM_NAME MATCHES "MINGW"))
	set(BUILD_NC false)
	add_definitions(-D_GNU_SOURCE)
	add_definitions(-D_POSIX)
	add_definitions(-D_POSIX_SOURCE)
	add_definitions(-D__USE_MINGW_ANSI_STDIO)
endif()

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -Wall")

if(CMAKE_SYSTEM_NAME MATCHES "HP-UX")
	if(CMAKE_C_COMPILER MATCHES "gcc")
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu99 -fno-strict-aliasing")
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mlp64")
	else()
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} +DD64 +Otype_safety=off")
	endif()
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D_XOPEN_SOURCE=600 -D__STRICT_ALIGNMENT")
	set(PLATFORM_LIBS ${PLATFORM_LIBS} pthread)
endif()

if(CMAKE_SYSTEM_NAME MATCHES "SunOS")
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu99 -fno-strict-aliasing")
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D__EXTENSIONS__")
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D_XOPEN_SOURCE=600")
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DBSD_COMP")
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fpic")
	set(PLATFORM_LIBS ${PLATFORM_LIBS} dl md nsl socket)
endif()

add_definitions(-DLIBRESSL_INTERNAL)
add_definitions(-DOPENSSL_NO_HW_PADLOCK)
add_definitions(-D__BEGIN_HIDDEN_DECLS=)
add_definitions(-D__END_HIDDEN_DECLS=)

set(CMAKE_POSITION_INDEPENDENT_CODE true)

if (CMAKE_COMPILER_IS_GNUCC OR CMAKE_C_COMPILER_ID MATCHES "Clang")
	add_definitions(-Wno-pointer-sign)
endif()

if(WIN32)
	add_definitions(-D_CRT_SECURE_NO_WARNINGS)
	add_definitions(-D_CRT_DEPRECATED_NO_WARNINGS)
	add_definitions(-D_REENTRANT -D_POSIX_THREAD_SAFE_FUNCTIONS)
	add_definitions(-DCPPFLAGS -DNO_SYSLOG -DNO_CRYPT)
	add_definitions(-DWIN32_LEAN_AND_MEAN)
	if(NOT CMAKE_SYSTEM_NAME MATCHES "WindowsStore")
		add_definitions(-D_WIN32_WINNT=0x0600)
	endif()
	set(PLATFORM_LIBS ${PLATFORM_LIBS} ws2_32 bcrypt)
endif()

if(MSVC)
	add_definitions(-Dinline=__inline)
	message(STATUS "Using [${CMAKE_C_COMPILER_ID}] compiler")
	if(CMAKE_C_COMPILER_ID MATCHES "MSVC" OR CMAKE_C_COMPILER_ID MATCHES "Clang")
		set(MSVC_DISABLED_WARNINGS_LIST
			"C4018" # 'expression' : signed/unsigned mismatch
			"C4057" # 'operator' : 'identifier1' indirection to
		        	# slightly different base types from 'identifier2'
			"C4100" # 'identifier' : unreferenced formal parameter
			"C4127" # conditional expression is constant
			"C4146" # unary minus operator applied to unsigned type,
				# result still unsigned
			"C4244" # 'argument' : conversion from 'type1' to 'type2',
				# possible loss of data
			"C4245" # 'conversion' : conversion from 'type1' to 'type2',
				# signed/unsigned mismatch
			"C4267" # 'var' : conversion from 'size_t' to 'type',
				# possible loss of data
			"C4389" # 'operator' : signed/unsigned mismatch
			"C4706" # assignment within conditional expression
			"C4996" # The POSIX name for this item is deprecated.
				# Instead, use the ISO C and C++ conformant name
		)
	elseif(CMAKE_C_COMPILER_ID MATCHES "Intel")
		add_definitions(-D_CRT_SUPPRESS_RESTRICT)
		set(MSVC_DISABLED_WARNINGS_LIST
			"C111"  # Unreachable statement
			"C128"  # Unreachable loop
			"C167"  # Unexplict casting unsigned to signed
			"C186"  # Pointless comparison of unsigned int with zero
			"C188"  # Enumerated type mixed with another type
			"C344"  # Redeclared type
			"C556"  # Unexplict casting signed to unsigned
			"C869"  # Unreferenced parameters
			"C1786" # Deprecated functions
			"C2545" # Empty else statement
			"C2557" # Comparing signed to unsigned
			"C2722" # List init syntax is c++11 feature
			"C3280" # Declaration hides variable
		)
	endif()
	string(REPLACE "C" " -wd" MSVC_DISABLED_WARNINGS_STR
		${MSVC_DISABLED_WARNINGS_LIST})
	string(REGEX REPLACE "[/-]W[1234][ ]?" "" CMAKE_C_FLAGS ${CMAKE_C_FLAGS})
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -MP -W4 ${MSVC_DISABLED_WARNINGS_STR}")
endif()

check_function_exists(asprintf HAVE_ASPRINTF)
if(HAVE_ASPRINTF)
	add_definitions(-DHAVE_ASPRINTF)
endif()

check_function_exists(reallocarray HAVE_REALLOCARRAY)
if(HAVE_REALLOCARRAY)
	add_definitions(-DHAVE_REALLOCARRAY)
endif()

check_function_exists(strcasecmp HAVE_STRCASECMP)
if(HAVE_STRCASECMP)
	add_definitions(-DHAVE_STRCASECMP)
endif()

check_function_exists(strlcat HAVE_STRLCAT)
if(HAVE_STRLCAT)
	add_definitions(-DHAVE_STRLCAT)
endif()

check_function_exists(strlcpy HAVE_STRLCPY)
if(HAVE_STRLCPY)
	add_definitions(-DHAVE_STRLCPY)
endif()

check_function_exists(strndup HAVE_STRNDUP)
if(HAVE_STRNDUP)
	add_definitions(-DHAVE_STRNDUP)
endif()

if(WIN32)
	set(HAVE_STRNLEN true)
	add_definitions(-DHAVE_STRNLEN)
else()
	check_function_exists(strnlen HAVE_STRNLEN)
	if(HAVE_STRNLEN)
		add_definitions(-DHAVE_STRNLEN)
	endif()
endif()

check_function_exists(strsep HAVE_STRSEP)
if(HAVE_STRSEP)
	add_definitions(-DHAVE_STRSEP)
endif()

check_function_exists(timegm HAVE_TIMEGM)
if(HAVE_TIMEGM)
	add_definitions(-DHAVE_TIMEGM)
endif()

check_function_exists(arc4random_buf HAVE_ARC4RANDOM_BUF)
if(HAVE_ARC4RANDOM_BUF)
	add_definitions(-DHAVE_ARC4RANDOM_BUF)
endif()

check_function_exists(arc4random_uniform HAVE_ARC4RANDOM_UNIFORM)
if(HAVE_ARC4RANDOM_UNIFORM)
	add_definitions(-DHAVE_ARC4RANDOM_UNIFORM)
endif()

check_function_exists(explicit_bzero HAVE_EXPLICIT_BZERO)
if(HAVE_EXPLICIT_BZERO)
	add_definitions(-DHAVE_EXPLICIT_BZERO)
endif()

check_function_exists(getauxval HAVE_GETAUXVAL)
if(HAVE_GETAUXVAL)
	add_definitions(-DHAVE_GETAUXVAL)
endif()

check_function_exists(getentropy HAVE_GETENTROPY)
if(HAVE_GETENTROPY)
	add_definitions(-DHAVE_GETENTROPY)
endif()

check_symbol_exists(getpagesize unistd.h HAVE_GETPAGESIZE)
if(HAVE_GETPAGESIZE)
	add_definitions(-DHAVE_GETPAGESIZE)
endif()

check_function_exists(getprogname HAVE_GETPROGNAME)
if(HAVE_GETPROGNAME)
	add_definitions(-DHAVE_GETPROGNAME)
endif()

check_function_exists(syslog_r HAVE_SYSLOG_R)
if(HAVE_SYSLOG_R)
	add_definitions(-DHAVE_SYSLOG_R)
endif()

check_function_exists(syslog HAVE_SYSLOG)
if(HAVE_SYSLOG)
	add_definitions(-DHAVE_SYSLOG)
endif()

check_symbol_exists(timespecsub sys/time.h HAVE_TIMESPECSUB)
if(HAVE_TIMESPECSUB)
	add_definitions(-DHAVE_TIMESPECSUB)
endif()

check_function_exists(timingsafe_bcmp HAVE_TIMINGSAFE_BCMP)
if(HAVE_TIMINGSAFE_BCMP)
	add_definitions(-DHAVE_TIMINGSAFE_BCMP)
endif()

check_function_exists(timingsafe_memcmp HAVE_TIMINGSAFE_MEMCMP)
if(HAVE_MEMCMP)
	add_definitions(-DHAVE_MEMCMP)
endif()

check_function_exists(memmem HAVE_MEMMEM)
if(HAVE_MEMMEM)
	add_definitions(-DHAVE_MEMMEM)
endif()

check_include_files(endian.h HAVE_ENDIAN_H)
if(HAVE_ENDIAN_H)
	add_definitions(-DHAVE_ENDIAN_H)
endif()

check_include_files(err.h HAVE_ERR_H)
if(HAVE_ERR_H)
	add_definitions(-DHAVE_ERR_H)
endif()

check_include_files("sys/types.h;arpa/inet.h;netinet/ip.h" HAVE_NETINET_IP_H)
if(HAVE_NETINET_IP_H)
	add_definitions(-DHAVE_NETINET_IP_H)
endif()

if(ENABLE_ASM)
	if("${CMAKE_C_COMPILER_ABI}" STREQUAL "ELF")
		if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "(x86_64|amd64)")
			set(HOST_ASM_ELF_X86_64 true)
		elseif("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "arm")
			set(HOST_ASM_ELF_ARMV4 true)
		elseif(CMAKE_SYSTEM_NAME STREQUAL "SunOS" AND "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "i386")
			set(HOST_ASM_ELF_X86_64 true)
		endif()
		add_definitions(-DHAVE_GNU_STACK)
	elseif(APPLE AND "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
		set(HOST_ASM_MACOSX_X86_64 true)
	elseif(MSVC AND ("${CMAKE_GENERATOR}" MATCHES "Win64" OR "${CMAKE_GENERATOR_PLATFORM}" STREQUAL "x64"))
		set(HOST_ASM_MASM_X86_64 true)
		ENABLE_LANGUAGE(ASM_MASM)
	elseif(CMAKE_SYSTEM_NAME MATCHES "MINGW" AND "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
		set(HOST_ASM_MINGW64_X86_64 true)
	endif()
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Linux")
	# Check if we need -lrt to get clock_gettime on Linux
	check_library_exists(rt clock_gettime "time.h" HAVE_CLOCK_GETTIME)
	if (HAVE_CLOCK_GETTIME)
		set(PLATFORM_LIBS ${PLATFORM_LIBS} rt)
	endif()
else()
	# Otherwise, simply check if it exists
	check_function_exists(clock_gettime HAVE_CLOCK_GETTIME)
endif()
if(HAVE_CLOCK_GETTIME)
	add_definitions(-DHAVE_CLOCK_GETTIME)
endif()

check_type_size(time_t SIZEOF_TIME_T)
if(SIZEOF_TIME_T STREQUAL "4")
	set(SMALL_TIME_T true)
	add_definitions(-DSMALL_TIME_T)
	message(WARNING " ** Warning, this system is unable to represent times past 2038\n"
	                " ** It will behave incorrectly when handling valid RFC5280 dates")
endif()
add_definitions(-DSIZEOF_TIME_T=${SIZEOF_TIME_T})

set(OPENSSL_LIBS ssl crypto ${PLATFORM_LIBS})
set(LIBTLS_LIBS tls ${PLATFORM_LIBS})

# libraries for regression test
if(BUILD_SHARED_LIBS)
	set(OPENSSL_TEST_LIBS ssl-static crypto-static ${PLATFORM_LIBS})
	set(LIBTLS_TEST_LIBS tls-static ${PLATFORM_LIBS})
else()
	set(OPENSSL_TEST_LIBS ssl crypto ${PLATFORM_LIBS})
	set(LIBTLS_TEST_LIBS tls ${PLATFORM_LIBS})
endif()

add_subdirectory(crypto)
add_subdirectory(ssl)
if(LIBRESSL_APPS)
	add_subdirectory(apps)
endif()
add_subdirectory(tls)
add_subdirectory(include)
if(NOT MSVC)
	add_subdirectory(man)
endif()
# Tests require the openssl executable and are unavailable when building shared libraries
if(LIBRESSL_APPS AND LIBRESSL_TESTS)
	add_subdirectory(tests)
endif()

if (BUILD_APPLE_XCFRAMEWORK)
	# Create the super library from object libraries
	add_library(LibreSSL_xcframework
			$<TARGET_OBJECTS:crypto_obj> $<TARGET_OBJECTS:tls_obj> $<TARGET_OBJECTS:ssl_obj>)
	set_target_properties(LibreSSL_xcframework PROPERTIES
			OUTPUT_NAME ressl)

	if(ENABLE_LIBRESSL_INSTALL)
		install(TARGETS LibreSSL_xcframework
				LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
	endif(ENABLE_LIBRESSL_INSTALL)
endif(BUILD_APPLE_XCFRAMEWORK)

if(ENABLE_LIBRESSL_INSTALL)
	if(NOT MSVC)
		# Create pkgconfig files.
		set(prefix      ${CMAKE_INSTALL_PREFIX})
		set(exec_prefix \${prefix})
		set(libdir      \${exec_prefix}/${CMAKE_INSTALL_LIBDIR})
		set(includedir  \${prefix}/include)
		if(PLATFORM_LIBS)
			string(REGEX REPLACE ";" " -l" PLATFORM_LDADD ";${PLATFORM_LIBS}")
		endif()
		file(STRINGS    "VERSION" VERSION LIMIT_COUNT 1)
		file(GLOB       OPENSSL_PKGCONFIGS "*.pc.in")
		foreach(file ${OPENSSL_PKGCONFIGS})
			get_filename_component(filename ${file} NAME)
			string(REPLACE ".in" "" new_file "${filename}")
			configure_file(${filename} pkgconfig/${new_file} @ONLY)
		endforeach()
		install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/pkgconfig
			DESTINATION ${CMAKE_INSTALL_LIBDIR})
	endif()
endif(ENABLE_LIBRESSL_INSTALL)

if(NOT "${OPENSSLDIR}" STREQUAL "")
	set(CONF_DIR "${OPENSSLDIR}")
else()
	set(CONF_DIR "${CMAKE_INSTALL_PREFIX}/etc/ssl")
endif()

if(ENABLE_LIBRESSL_INSTALL)
	install(FILES cert.pem openssl.cnf x509v3.cnf DESTINATION ${CONF_DIR})
	install(DIRECTORY DESTINATION ${CONF_DIR}/certs)
endif(ENABLE_LIBRESSL_INSTALL)

if(NOT TARGET uninstall)
	configure_file(
		"${CMAKE_CURRENT_SOURCE_DIR}/cmake_uninstall.cmake.in"
		"${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
		IMMEDIATE @ONLY)

	add_custom_target(uninstall
		COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake)
endif()
