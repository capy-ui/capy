set(
	SSL_SRC
	bio_ssl.c
	d1_both.c
	d1_lib.c
	d1_pkt.c
	d1_srtp.c
	pqueue.c
	s3_cbc.c
	s3_lib.c
	ssl_algs.c
	ssl_asn1.c
	ssl_both.c
	ssl_cert.c
	ssl_ciph.c
	ssl_ciphers.c
	ssl_clnt.c
	ssl_err.c
	ssl_init.c
	ssl_kex.c
	ssl_lib.c
	ssl_methods.c
	ssl_packet.c
	ssl_pkt.c
	ssl_rsa.c
	ssl_seclevel.c
	ssl_sess.c
	ssl_sigalgs.c
	ssl_srvr.c
	ssl_stat.c
	ssl_tlsext.c
	ssl_transcript.c
	ssl_txt.c
	ssl_versions.c
	t1_enc.c
	t1_lib.c
	tls_buffer.c
	tls_content.c
	tls_key_share.c
	tls_lib.c
	tls12_key_schedule.c
	tls12_lib.c
	tls12_record_layer.c
	tls13_client.c
	tls13_error.c
	tls13_handshake.c
	tls13_handshake_msg.c
	tls13_key_schedule.c
	tls13_legacy.c
	tls13_lib.c
	tls13_quic.c
	tls13_record.c
	tls13_record_layer.c
	tls13_server.c
)

set(
	BS_SRC
	bs_ber.c
	bs_cbb.c
	bs_cbs.c
)

add_library(ssl_obj OBJECT ${SSL_SRC})
target_include_directories(ssl_obj
	PRIVATE
		.
		../crypto/bio
		../include/compat
	PUBLIC
		../include)

add_library(bs_obj OBJECT ${BS_SRC})
target_include_directories(bs_obj
	PRIVATE
		.
		../include/compat)

if(BUILD_SHARED_LIBS)
	add_library(ssl $<TARGET_OBJECTS:ssl_obj> $<TARGET_OBJECTS:bs_obj>)
else()
	add_library(ssl $<TARGET_OBJECTS:ssl_obj>)
endif()

export_symbol(ssl ${CMAKE_CURRENT_SOURCE_DIR}/ssl.sym)
target_link_libraries(ssl crypto ${PLATFORM_LIBS})
if (WIN32)
	set(SSL_POSTFIX -${SSL_MAJOR_VERSION})
endif()
set_target_properties(ssl PROPERTIES
	OUTPUT_NAME ssl${SSL_POSTFIX}
	ARCHIVE_OUTPUT_NAME ssl${SSL_POSTFIX})
set_target_properties(ssl PROPERTIES VERSION ${SSL_VERSION}
	SOVERSION ${SSL_MAJOR_VERSION})

if(ENABLE_LIBRESSL_INSTALL)
	install(
		TARGETS ssl
		ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
		LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
		RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
	)
endif(ENABLE_LIBRESSL_INSTALL)

# build static library for regression test
if(BUILD_SHARED_LIBS)
	add_library(ssl-static STATIC $<TARGET_OBJECTS:ssl_obj>)
	target_link_libraries(ssl-static crypto-static ${PLATFORM_LIBS})
endif()

