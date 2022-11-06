AC_DEFUN([CHECK_OS_OPTIONS], [

CFLAGS="$CFLAGS -Wall -std=gnu99 -fno-strict-aliasing"
BUILD_NC=yes

case $host_os in
	*aix*)
		HOST_OS=aix
		if test "`echo $CC | cut -d ' ' -f 1`" != "gcc" ; then
			CFLAGS="-qnoansialias $USER_CFLAGS"
		fi
		AC_SUBST([PLATFORM_LDADD], ['-lperfstat'])
		;;
	*cygwin*)
		HOST_OS=cygwin
		CPPFLAGS="$CPPFLAGS -D_GNU_SOURCE"
		;;
	*darwin*)
		HOST_OS=darwin
		HOST_ABI=macosx
		#
		# Don't use arc4random on systems before 10.12 because of
		# weak seed on failure to open /dev/random, based on latest
		# public source:
		# http://www.opensource.apple.com/source/Libc/Libc-997.90.3/gen/FreeBSD/arc4random.c
		#
		# We use the presence of getentropy() to detect 10.12. The
		# following check take into account that:
 		#
		#   - iOS <= 10.1 fails because of missing getentropy and
		#     hence they miss sys/random.h
		#
		#   - in macOS 10.12 getentropy is not tagged as introduced in
		#     10.12 so we cannot use it for target < 10.12
		#
		AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[
#include <AvailabilityMacros.h>
#include <unistd.h>
#include <sys/random.h>  /* Systems without getentropy() should die here */

/* Based on: https://gitweb.torproject.org/tor.git/commit/?id=16fcbd21 */
#ifndef MAC_OS_X_VERSION_10_12
#  define MAC_OS_X_VERSION_10_12 101200
#endif
#if defined(MAC_OS_X_VERSION_MIN_REQUIRED)
#  if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_12
#    error "Running on Mac OSX 10.11 or earlier"
#  endif
#endif
                       ]], [[
char buf[1]; getentropy(buf, 1);
					   ]])],
                       [ USE_BUILTIN_ARC4RANDOM=no ],
                       [ USE_BUILTIN_ARC4RANDOM=yes ]
		)
		AC_MSG_CHECKING([whether to use builtin arc4random])
		AC_MSG_RESULT([$USE_BUILTIN_ARC4RANDOM])
		# Not available on iOS
		AC_CHECK_HEADER([arpa/telnet.h], [], [BUILD_NC=no])
		;;
	*freebsd*)
		HOST_OS=freebsd
		HOST_ABI=elf
		# fork detection missing, weak seed on failure
		# https://svnweb.freebsd.org/base/head/lib/libc/gen/arc4random.c?revision=268642&view=markup
		USE_BUILTIN_ARC4RANDOM=yes
		AC_SUBST([PROG_LDADD], ['-lthr'])
		;;
	*hpux*)
		HOST_OS=hpux;
		if test "`echo $host_os | cut -c 1-4`" = "ia64" ; then
			if test "`echo $CC | cut -d ' ' -f 1`" = "gcc" ; then
				CFLAGS="$CFLAGS -mlp64"
			else
				CFLAGS="+DD64"
			fi
		fi
		if ! test "`echo $CC | cut -d ' ' -f 1`" = "gcc" ; then
			CFLAGS="-g -O2 +Otype_safety=off $CFLAGS $USER_CFLAGS"
		fi
		CPPFLAGS="$CPPFLAGS -D_XOPEN_SOURCE=600 -D__STRICT_ALIGNMENT"
		;;
	*linux*)
		HOST_OS=linux
		HOST_ABI=elf
		CPPFLAGS="$CPPFLAGS -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_POSIX_SOURCE -D_GNU_SOURCE"
		;;
	*midipix*)
		HOST_OS=midipix
		CPPFLAGS="$CPPFLAGS -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_POSIX_SOURCE -D_GNU_SOURCE"
		;;
	*netbsd*)
		HOST_OS=netbsd
		HOST_ABI=elf
		AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[
#include <sys/param.h>
#if __NetBSD_Version__ < 700000001
        undefined
#endif
                       ]], [[]])],
                       [ USE_BUILTIN_ARC4RANDOM=no ],
                       [ USE_BUILTIN_ARC4RANDOM=yes ]
		)
		CPPFLAGS="$CPPFLAGS -D_OPENBSD_SOURCE"
		;;
	*openbsd* | *bitrig*)
		HOST_OS=openbsd
		HOST_ABI=elf
		AC_DEFINE([HAVE_ATTRIBUTE__BOUNDED__], [1], [OpenBSD gcc has bounded])
		AC_DEFINE([HAVE_ATTRIBUTE__DEAD], [1], [OpenBSD gcc has __dead])
		;;
	*mingw*)
		HOST_OS=win
		HOST_ABI=mingw64
		BUILD_NC=no
		CPPFLAGS="$CPPFLAGS -D_GNU_SOURCE -D_POSIX -D_POSIX_SOURCE -D__USE_MINGW_ANSI_STDIO"
		CPPFLAGS="$CPPFLAGS -D_REENTRANT -D_POSIX_THREAD_SAFE_FUNCTIONS"
		CPPFLAGS="$CPPFLAGS -DWIN32_LEAN_AND_MEAN -D_WIN32_WINNT=0x0600"
		CPPFLAGS="$CPPFLAGS"
		AC_SUBST([PLATFORM_LDADD], ['-lws2_32 -lbcrypt'])
		;;
	*solaris*)
		HOST_OS=solaris
		HOST_ABI=elf
		CPPFLAGS="$CPPFLAGS -D__EXTENSIONS__ -D_XOPEN_SOURCE=600 -DBSD_COMP"
		AC_SUBST([PLATFORM_LDADD], ['-ldl -lmd -lnsl -lsocket'])
		;;
	*) ;;
esac

# Check if time_t is sized correctly
AC_CHECK_SIZEOF([time_t], [time.h])
AM_CONDITIONAL([SMALL_TIME_T], [test "$ac_cv_sizeof_time_t" = "4"])
if test "$ac_cv_sizeof_time_t" = "4"; then
    AC_DEFINE([SMALL_TIME_T])
    echo " ** Warning, this system is unable to represent times past 2038"
    echo " ** It will behave incorrectly when handling valid RFC5280 dates"

    if test "$host_os" = "mingw32" ; then
        echo " **"
        echo " ** You can solve this by adjusting the build flags in your"
        echo " ** mingw-w64 toolchain. Refer to README.windows for details."
    fi
fi

AM_CONDITIONAL([HOST_AIX],     [test x$HOST_OS = xaix])
AM_CONDITIONAL([HOST_CYGWIN],  [test x$HOST_OS = xcygwin])
AM_CONDITIONAL([HOST_DARWIN],  [test x$HOST_OS = xdarwin])
AM_CONDITIONAL([HOST_FREEBSD], [test x$HOST_OS = xfreebsd])
AM_CONDITIONAL([HOST_HPUX],    [test x$HOST_OS = xhpux])
AM_CONDITIONAL([HOST_LINUX],   [test x$HOST_OS = xlinux])
AM_CONDITIONAL([HOST_MIDIPIX], [test x$HOST_OS = xmidipix])
AM_CONDITIONAL([HOST_NETBSD],  [test x$HOST_OS = xnetbsd])
AM_CONDITIONAL([HOST_OPENBSD], [test x$HOST_OS = xopenbsd])
AM_CONDITIONAL([HOST_SOLARIS], [test x$HOST_OS = xsolaris])
AM_CONDITIONAL([HOST_WIN],     [test x$HOST_OS = xwin])
])
