/*
 * Public domain
 * sys/time.h compatibility shim
 */

#ifdef _MSC_VER
#if _MSC_VER >= 1900
#include <../ucrt/time.h>
#else
#include <../include/time.h>
#endif
#else
#include_next <time.h>
#endif

#ifndef LIBCRYPTOCOMPAT_TIME_H
#define LIBCRYPTOCOMPAT_TIME_H

#ifdef _WIN32
struct tm *__gmtime_r(const time_t * t, struct tm * tm);
#define gmtime_r(tp, tm) __gmtime_r(tp, tm)
#endif

#ifndef HAVE_TIMEGM
time_t timegm(struct tm *tm);
#endif

#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC CLOCK_REALTIME
#endif

#ifndef CLOCK_REALTIME
#define CLOCK_REALTIME 0
#endif

#ifndef _WIN32
#ifndef HAVE_CLOCK_GETTIME
typedef int clockid_t;
int clock_gettime(clockid_t clock_id, struct timespec *tp);
#endif

#ifdef timespecsub
#define HAVE_TIMESPECSUB
#endif

#ifndef HAVE_TIMESPECSUB
#define timespecsub(tsp, usp, vsp)                                      \
        do {                                                            \
                (vsp)->tv_sec = (tsp)->tv_sec - (usp)->tv_sec;          \
                (vsp)->tv_nsec = (tsp)->tv_nsec - (usp)->tv_nsec;       \
                if ((vsp)->tv_nsec < 0) {                               \
                        (vsp)->tv_sec--;                                \
                        (vsp)->tv_nsec += 1000000000L;                  \
                }                                                       \
        } while (0)
#endif

#endif

#endif
