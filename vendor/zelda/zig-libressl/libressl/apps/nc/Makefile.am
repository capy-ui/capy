include $(top_srcdir)/Makefile.am.common

-include $(abs_top_builddir)/crypto/libcrypto_la_objects.mk

if BUILD_NC

if ENABLE_NC
bin_PROGRAMS = nc
dist_man_MANS = nc.1
else
noinst_PROGRAMS = nc
endif

EXTRA_DIST = nc.1
EXTRA_DIST += CMakeLists.txt

nc_LDADD = $(abs_top_builddir)/tls/libtls.la
nc_LDADD += $(PLATFORM_LDADD) $(PROG_LDADD)

nc_LDADD += $(libcrypto_la_objects)
nc_LDADD += $(libcompat_la_objects)
nc_LDADD += $(libcompatnoopt_la_objects)

AM_CPPFLAGS += -I$(top_srcdir)/apps/nc/compat

nc_SOURCES = atomicio.c
nc_SOURCES += netcat.c
nc_SOURCES += socks.c
noinst_HEADERS = atomicio.h
noinst_HEADERS += compat/sys/socket.h

nc_SOURCES += compat/socket.c

if !HAVE_B64_NTOP
nc_SOURCES += compat/base64.c
endif

if !HAVE_ACCEPT4
nc_SOURCES += compat/accept4.c
endif

if !HAVE_READPASSPHRASE
nc_SOURCES += compat/readpassphrase.c
endif

endif
