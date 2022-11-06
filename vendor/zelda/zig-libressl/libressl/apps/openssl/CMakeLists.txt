set(
	OPENSSL_SRC
	apps.c
	asn1pars.c
	ca.c
	ciphers.c
	crl.c
	crl2p7.c
	cms.c
	dgst.c
	dh.c
	dhparam.c
	dsa.c
	dsaparam.c
	ec.c
	ecparam.c
	enc.c
	errstr.c
	gendh.c
	gendsa.c
	genpkey.c
	genrsa.c
	nseq.c
	ocsp.c
	openssl.c
	passwd.c
	pkcs12.c
	pkcs7.c
	pkcs8.c
	pkey.c
	pkeyparam.c
	pkeyutl.c
	prime.c
	rand.c
	req.c
	rsa.c
	rsautl.c
	s_cb.c
	s_client.c
	s_server.c
	s_socket.c
	s_time.c
	sess_id.c
	smime.c
	speed.c
	spkac.c
	ts.c
	verify.c
	version.c
	x509.c
)

if(UNIX)
	set(OPENSSL_SRC ${OPENSSL_SRC} apps_posix.c)
	set(OPENSSL_SRC ${OPENSSL_SRC} certhash.c)
endif()

if(WIN32)
	set(OPENSSL_SRC ${OPENSSL_SRC} apps_win.c)
	set(OPENSSL_SRC ${OPENSSL_SRC} certhash_win.c)
	set(OPENSSL_SRC ${OPENSSL_SRC} compat/poll_win.c)
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Darwin")
        check_function_exists(clock_gettime HAVE_CLOCK_GETTIME)
        if(NOT HAVE_CLOCK_GETTIME)
                set(OPENSSL_SRC ${OPENSSL_SRC} compat/clock_gettime_osx.c)
        endif()
endif()

add_executable(openssl ${OPENSSL_SRC})
target_include_directories(openssl PUBLIC ../../include)
target_include_directories(openssl PRIVATE . ../../include/compat)
target_link_libraries(openssl ${OPENSSL_LIBS})

if(ENABLE_LIBRESSL_INSTALL)
	install(TARGETS openssl DESTINATION ${CMAKE_INSTALL_BINDIR})
	install(FILES openssl.1 DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
endif(ENABLE_LIBRESSL_INSTALL)
