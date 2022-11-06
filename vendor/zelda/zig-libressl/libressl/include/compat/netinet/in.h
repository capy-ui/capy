/*
 * Public domain
 * netinet/in.h compatibility shim
 */

#ifndef _WIN32
#include_next <netinet/in.h>
#else
#include <win32netcompat.h>
#endif

#ifndef LIBCRYPTOCOMPAT_NETINET_IN_H
#define LIBCRYPTOCOMPAT_NETINET_IN_H

#ifdef __ANDROID__
typedef uint16_t in_port_t;
#endif

#endif
