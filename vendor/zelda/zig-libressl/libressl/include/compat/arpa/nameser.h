/*
 * Public domain
 * arpa/inet.h compatibility shim
 */

#ifndef _WIN32
#ifdef HAVE_ARPA_NAMESER_H
#include_next <arpa/nameser.h>
#endif
#else
#include <win32netcompat.h>

#ifndef INADDRSZ
#define INADDRSZ 4
#endif

#ifndef IN6ADDRSZ
#define IN6ADDRSZ 16
#endif

#ifndef INT16SZ
#define INT16SZ	2
#endif

#endif
