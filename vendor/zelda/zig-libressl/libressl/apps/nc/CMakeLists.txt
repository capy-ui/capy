if(BUILD_NC)

set(
	NC_SRC
	atomicio.c
	netcat.c
	socks.c
	compat/socket.c
)

check_function_exists(b64_ntop HAVE_B64_NTOP)
if(HAVE_B64_NTOP)
	add_definitions(-DHAVE_B64_NTOP)
else()
	set(NC_SRC ${NC_SRC} compat/base64.c)
endif()

check_function_exists(accept4 HAVE_ACCEPT4)
if(HAVE_ACCEPT4)
	add_definitions(-DHAVE_ACCEPT4)
else()
	set(NC_SRC ${NC_SRC} compat/accept4.c)
endif()

check_function_exists(readpassphrase HAVE_READPASSPHRASE)
if(HAVE_READPASSPHRASE)
	add_definitions(-DHAVE_READPASSPHRASE)
else()
	set(NC_SRC ${NC_SRC} compat/readpassphrase.c)
endif()

if(NOT "${OPENSSLDIR}" STREQUAL "")
	add_definitions(-DDEFAULT_CA_FILE=\"${OPENSSLDIR}/cert.pem\")
else()
	add_definitions(-DDEFAULT_CA_FILE=\"${CMAKE_INSTALL_PREFIX}/etc/ssl/cert.pem\")
endif()

add_executable(nc ${NC_SRC})
target_include_directories(nc PUBLIC ../../include)
target_include_directories(nc PRIVATE . ./compat ../../include/compat)
target_link_libraries(nc ${LIBTLS_LIBS})

if(ENABLE_NC)
	if(ENABLE_LIBRESSL_INSTALL)
		install(TARGETS nc DESTINATION ${CMAKE_INSTALL_BINDIR})
		install(FILES nc.1 DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
	endif(ENABLE_LIBRESSL_INSTALL)
endif()

endif()
