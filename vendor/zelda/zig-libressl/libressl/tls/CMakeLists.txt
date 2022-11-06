set(
	TLS_SRC
	tls.c
	tls_bio_cb.c
	tls_client.c
	tls_config.c
	tls_conninfo.c
	tls_keypair.c
	tls_server.c
	tls_signer.c
	tls_ocsp.c
	tls_peer.c
	tls_util.c
	tls_verify.c
)

if(WIN32)
	set(
		TLS_SRC
		${TLS_SRC}
		compat/ftruncate.c
		compat/pread.c
		compat/pwrite.c
	)
endif()

if(NOT "${OPENSSLDIR}" STREQUAL "")
	add_definitions(-DTLS_DEFAULT_CA_FILE=\"${OPENSSLDIR}/cert.pem\")
else()
	add_definitions(-DTLS_DEFAULT_CA_FILE=\"${CMAKE_INSTALL_PREFIX}/etc/ssl/cert.pem\")
endif()

file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/tls.sym DESTINATION
	${CMAKE_CURRENT_BINARY_DIR})
if(LIBTLS_EXTRA_EXPORT)
	list(SORT LIBTLS_EXTRA_EXPORT)
	foreach(SYM IN LISTS LIBTLS_EXTRA_EXPORT)
		file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/tls.sym "${SYM}\n")
	endforeach()
endif()

add_library(tls_obj OBJECT ${TLS_SRC})
target_include_directories(tls_obj
	PRIVATE
		.
		../include/compat
	PUBLIC
		../include)

add_library(tls $<TARGET_OBJECTS:tls_obj> $<TARGET_OBJECTS:ssl_obj>
	$<TARGET_OBJECTS:crypto_obj>)

export_symbol(tls ${CMAKE_CURRENT_BINARY_DIR}/tls.sym)
target_link_libraries(tls ${PLATFORM_LIBS})
if (WIN32)
	set(TLS_POSTFIX -${TLS_MAJOR_VERSION})
endif()
set_target_properties(tls PROPERTIES
	OUTPUT_NAME tls${TLS_POSTFIX}
	ARCHIVE_OUTPUT_NAME tls${TLS_POSTFIX})
set_target_properties(tls PROPERTIES VERSION ${TLS_VERSION}
	SOVERSION ${TLS_MAJOR_VERSION})

if(ENABLE_LIBRESSL_INSTALL)
	install(
		TARGETS tls
		ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
		LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
		RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
	)
endif(ENABLE_LIBRESSL_INSTALL)

# build static library for regression test
if(BUILD_SHARED_LIBS)
	add_library(tls-static STATIC $<TARGET_OBJECTS:tls_obj>
		$<TARGET_OBJECTS:ssl_obj> $<TARGET_OBJECTS:crypto_obj>)
	target_link_libraries(tls-static ${PLATFORM_LIBS})
endif()

