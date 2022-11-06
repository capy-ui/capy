# Copyright (c) 2014-2015 Brent Cook
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

AC_INIT([libressl], m4_esyscmd(tr -d '\n' < VERSION))
AC_SUBST([LIBCRYPTO_VERSION], m4_esyscmd([tr -d '\n' < crypto/VERSION]))
AC_SUBST([LIBSSL_VERSION], m4_esyscmd([tr -d '\n' < ssl/VERSION]))
AC_SUBST([LIBTLS_VERSION], m4_esyscmd([tr -d '\n' < tls/VERSION]))

AC_CANONICAL_HOST
AM_INIT_AUTOMAKE([subdir-objects foreign])
AC_CONFIG_MACRO_DIR([m4])

m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])

# This must be saved before AC_PROG_CC
USER_CFLAGS="$CFLAGS"

AC_PROG_CC([cc gcc])
AM_PROG_CC_C_O
LT_INIT([pic-only])

CHECK_OS_OPTIONS

CHECK_C_HARDENING_OPTIONS

DISABLE_AS_EXECUTABLE_STACK
AM_PROG_AS

DISABLE_COMPILER_WARNINGS

# Check if the certhash command should be built
AC_CHECK_FUNCS([symlink])
AM_CONDITIONAL([BUILD_CERTHASH], [test "x$ac_cv_func_symlink" = xyes])

# Check if funopen exists
AC_CHECK_FUNC([funopen])

CHECK_LIBC_COMPAT
CHECK_SYSCALL_COMPAT
CHECK_CRYPTO_COMPAT
CHECK_VA_COPY
CHECK_B64_NTOP

AC_ARG_WITH([openssldir],
	AS_HELP_STRING([--with-openssldir],
		       [Set the default openssl directory]),
	OPENSSLDIR="$withval"
	AC_SUBST(OPENSSLDIR)
)
AM_CONDITIONAL([OPENSSLDIR_DEFINED], [test x$with_openssldir != x])

AC_ARG_ENABLE([extratests],
	AS_HELP_STRING([--enable-extratests], [Enable extra tests that may be unreliable on some platforms]))
AM_CONDITIONAL([ENABLE_EXTRATESTS], [test "x$enable_extratests" = xyes])

AC_ARG_ENABLE([tests],
       [AS_HELP_STRING([--disable-tests], [Disable tests @<:@default=enabled@:>@])],
       [
        if ! test "x${enable_tests}" = "xyes"; then
		enable_tests="no"
	fi],
       [enable_tests="yes"])
AM_CONDITIONAL([ENABLE_TESTS], [test "x$enable_tests" = xyes])

AS_CASE([$host_cpu],
	[*arm*], [host_cpu=arm],
	[*amd64*], [host_cpu=x86_64 HOSTARCH=intel],
	[i?86], [HOSTARCH=intel],
	[x86_64], [HOSTARCH=intel]
)
AM_CONDITIONAL([HOST_CPU_IS_INTEL], [test "x$HOSTARCH" = "xintel"])

AC_MSG_CHECKING([if .gnu.warning accepts long strings])
AC_LINK_IFELSE([AC_LANG_SOURCE([[
extern void SSLv3_method();
__asm__(".section .gnu.warning.SSLv3_method\n\t.ascii \"SSLv3_method is insecure\"\n\t.text");
int main() {return 0;}
]])], [
    AC_DEFINE(HAS_GNU_WARNING_LONG, 1, [Define if .gnu.warning accepts long strings.])
    AC_MSG_RESULT(yes)
], [
   AC_MSG_RESULT(no)
])

AC_ARG_ENABLE([asm],
	AS_HELP_STRING([--disable-asm], [Disable assembly]))
AM_CONDITIONAL([OPENSSL_NO_ASM], [test "x$enable_asm" = "xno"])

# Conditionally enable assembly by default
AM_CONDITIONAL([HOST_ASM_ELF_ARM],
    [test "x$HOST_ABI" = "xelf" -a "$host_cpu" = "arm" -a "x$enable_asm" != "xno"])
AM_CONDITIONAL([HOST_ASM_ELF_X86_64],
    [test "x$HOST_ABI" = "xelf" -a "$host_cpu" = "x86_64" -a "x$enable_asm" != "xno"])
AM_CONDITIONAL([HOST_ASM_MACOSX_X86_64],
    [test "x$HOST_ABI" = "xmacosx" -a "$host_cpu" = "x86_64" -a "x$enable_asm" != "xno"])
AM_CONDITIONAL([HOST_ASM_MASM_X86_64],
    [test "x$HOST_ABI" = "xmasm" -a "$host_cpu" = "x86_64" -a "x$enable_asm" != "xno"])
AM_CONDITIONAL([HOST_ASM_MINGW64_X86_64],
    [test "x$HOST_ABI" = "xmingw64" -a "$host_cpu" = "x86_64" -a "x$enable_asm" != "xno"])

AC_CONFIG_FILES([
	Makefile
	include/Makefile
	include/openssl/Makefile
	crypto/Makefile
	ssl/Makefile
	tls/Makefile
	tests/Makefile
	apps/Makefile
	apps/ocspcheck/Makefile
	apps/openssl/Makefile
	apps/nc/Makefile
	man/Makefile
	libcrypto.pc
	libssl.pc
	libtls.pc
	openssl.pc
])

AC_ARG_ENABLE([nc],
	AS_HELP_STRING([--enable-nc], [Enable installing TLS-enabled nc(1)]))
AM_CONDITIONAL([ENABLE_NC], [test "x$enable_nc" = xyes])
AM_CONDITIONAL([BUILD_NC],  [test x$BUILD_NC = xyes -o "x$enable_nc" = xyes])

AC_ARG_ENABLE([libtls-only],
	AS_HELP_STRING([--enable-libtls-only], [Enable installing libtls only]))
AM_CONDITIONAL([ENABLE_LIBTLS_ONLY], [test "x$enable_libtls_only" = xyes])

AC_REQUIRE_AUX_FILE([tap-driver.sh])

AC_OUTPUT
