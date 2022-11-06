include $(top_srcdir)/Makefile.am.common

AM_CPPFLAGS += -I$(top_srcdir)/crypto/bio

noinst_LTLIBRARIES = libbs.la

if ENABLE_LIBTLS_ONLY
noinst_LTLIBRARIES += libssl.la
else
lib_LTLIBRARIES = libssl.la
endif

noinst_DATA = remove_bs_objects

EXTRA_DIST = VERSION
EXTRA_DIST += CMakeLists.txt
EXTRA_DIST += ssl.sym

CLEANFILES = libssl_la_objects.mk

EXTRA_libssl_la_DEPENDENCIES = libssl_la_objects.mk

libssl_la_objects.mk: Makefile
	@echo "libssl_la_objects= $(libssl_la_OBJECTS)" \
	  | sed 's/  */ $$\(abs_top_builddir\)\/ssl\//g' \
	  > libssl_la_objects.mk

.PHONY: remove_bs_objects
remove_bs_objects: libssl.la
	-$(AR) dv $(abs_top_builddir)/ssl/.libs/libssl.a \
	    bs_ber.o bs_cbb.o bs_cbs.o

libssl_la_LDFLAGS = -version-info @LIBSSL_VERSION@ -no-undefined -export-symbols $(top_srcdir)/ssl/ssl.sym
libssl_la_LIBADD = $(abs_top_builddir)/crypto/libcrypto.la $(PLATFORM_LDADD)
libssl_la_LIBADD += libbs.la

libbs_la_SOURCES = bs_ber.c
libbs_la_SOURCES += bs_cbb.c
libbs_la_SOURCES += bs_cbs.c
noinst_HEADERS = bytestring.h

libssl_la_SOURCES = bio_ssl.c
libssl_la_SOURCES += d1_both.c
libssl_la_SOURCES += d1_lib.c
libssl_la_SOURCES += d1_pkt.c
libssl_la_SOURCES += d1_srtp.c
libssl_la_SOURCES += pqueue.c
libssl_la_SOURCES += s3_cbc.c
libssl_la_SOURCES += s3_lib.c
libssl_la_SOURCES += ssl_algs.c
libssl_la_SOURCES += ssl_asn1.c
libssl_la_SOURCES += ssl_both.c
libssl_la_SOURCES += ssl_cert.c
libssl_la_SOURCES += ssl_ciph.c
libssl_la_SOURCES += ssl_ciphers.c
libssl_la_SOURCES += ssl_clnt.c
libssl_la_SOURCES += ssl_err.c
libssl_la_SOURCES += ssl_init.c
libssl_la_SOURCES += ssl_kex.c
libssl_la_SOURCES += ssl_lib.c
libssl_la_SOURCES += ssl_methods.c
libssl_la_SOURCES += ssl_packet.c
libssl_la_SOURCES += ssl_pkt.c
libssl_la_SOURCES += ssl_rsa.c
libssl_la_SOURCES += ssl_seclevel.c
libssl_la_SOURCES += ssl_sess.c
libssl_la_SOURCES += ssl_sigalgs.c
libssl_la_SOURCES += ssl_srvr.c
libssl_la_SOURCES += ssl_stat.c
libssl_la_SOURCES += ssl_tlsext.c
libssl_la_SOURCES += ssl_transcript.c
libssl_la_SOURCES += ssl_txt.c
libssl_la_SOURCES += ssl_versions.c
libssl_la_SOURCES += t1_enc.c
libssl_la_SOURCES += t1_lib.c
libssl_la_SOURCES += tls_buffer.c
libssl_la_SOURCES += tls_content.c
libssl_la_SOURCES += tls_key_share.c
libssl_la_SOURCES += tls_lib.c
libssl_la_SOURCES += tls12_key_schedule.c
libssl_la_SOURCES += tls12_lib.c
libssl_la_SOURCES += tls12_record_layer.c
libssl_la_SOURCES += tls13_client.c
libssl_la_SOURCES += tls13_error.c
libssl_la_SOURCES += tls13_handshake.c
libssl_la_SOURCES += tls13_handshake_msg.c
libssl_la_SOURCES += tls13_key_schedule.c
libssl_la_SOURCES += tls13_legacy.c
libssl_la_SOURCES += tls13_lib.c
libssl_la_SOURCES += tls13_quic.c
libssl_la_SOURCES += tls13_record.c
libssl_la_SOURCES += tls13_record_layer.c
libssl_la_SOURCES += tls13_server.c

noinst_HEADERS += srtp.h
noinst_HEADERS += dtls_locl.h
noinst_HEADERS += ssl_locl.h
noinst_HEADERS += ssl_sigalgs.h
noinst_HEADERS += ssl_tlsext.h
noinst_HEADERS += tls_content.h
noinst_HEADERS += tls_internal.h
noinst_HEADERS += tls13_internal.h
noinst_HEADERS += tls13_handshake.h
noinst_HEADERS += tls13_record.h
