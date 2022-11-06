/*
 * Public domain
 * sys/time.h compatibility shim
 */

#ifndef LIBCRYPTOCOMPAT_SYS_TIME_H
#define LIBCRYPTOCOMPAT_SYS_TIME_H

#ifdef _MSC_VER
#include <winsock2.h>
int gettimeofday(struct timeval *tp, void *tzp);
#else
#include_next <sys/time.h>
#endif

#ifndef timersub
#define timersub(tvp, uvp, vvp)                                         \
	do {                                                            \
		(vvp)->tv_sec = (tvp)->tv_sec - (uvp)->tv_sec;          \
		(vvp)->tv_usec = (tvp)->tv_usec - (uvp)->tv_usec;       \
		if ((vvp)->tv_usec < 0) {                               \
			(vvp)->tv_sec--;                                \
			(vvp)->tv_usec += 1000000;                      \
		}                                                       \
	} while (0)
#endif

#endif
