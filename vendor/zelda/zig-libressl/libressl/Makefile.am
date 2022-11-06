SUBDIRS = crypto ssl tls include apps man
if ENABLE_TESTS
SUBDIRS += tests
endif
ACLOCAL_AMFLAGS = -I m4

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libtls.pc
if !ENABLE_LIBTLS_ONLY
pkgconfig_DATA += libcrypto.pc libssl.pc openssl.pc
endif

EXTRA_DIST = README.md README.windows VERSION config scripts
EXTRA_DIST += CMakeLists.txt cmake_export_symbol.cmake cmake_uninstall.cmake.in FindLibreSSL.cmake
EXTRA_DIST += cert.pem openssl.cnf x509v3.cnf

.PHONY: install_sw
install_sw: install

install-exec-hook:
	@if [ "@OPENSSLDIR@x" != "x" ]; then \
		OPENSSLDIR="$(DESTDIR)@OPENSSLDIR@"; \
	else \
		OPENSSLDIR="$(DESTDIR)$(sysconfdir)/ssl"; \
	fi; \
	mkdir -p "$$OPENSSLDIR/certs"; \
	for i in cert.pem openssl.cnf x509v3.cnf; do \
		if [ ! -f "$$OPENSSLDIR/$i" ]; then \
			$(INSTALL) -m 644 "$(srcdir)/$$i" "$$OPENSSLDIR/$$i"; \
		else \
			echo " $$OPENSSLDIR/$$i already exists, install will not overwrite"; \
		fi \
	done

uninstall-local:
	@if [ "@OPENSSLDIR@x" != "x" ]; then \
		OPENSSLDIR="$(DESTDIR)@OPENSSLDIR@"; \
	else \
		OPENSSLDIR="$(DESTDIR)$(sysconfdir)/ssl"; \
	fi; \
	for i in cert.pem openssl.cnf x509v3.cnf; do \
		if cmp -s "$$OPENSSLDIR/$$i" "$(srcdir)/$$i"; then \
			rm -f "$$OPENSSLDIR/$$i"; \
		fi \
	done
