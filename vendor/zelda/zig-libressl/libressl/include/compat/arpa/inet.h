/*
 * Public domain
 * arpa/inet.h compatibility shim
 */

#ifndef _WIN32
#include_next <arpa/inet.h>
#else
#include <win32netcompat.h>

#ifndef AI_ADDRCONFIG
#define AI_ADDRCONFIG               0x00000400
#endif

#endif
