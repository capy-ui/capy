/*
 * Public domain
 * endian.h compatibility shim
 */

#ifndef LIBCRYPTOCOMPAT_BYTE_ORDER_H_
#define LIBCRYPTOCOMPAT_BYTE_ORDER_H_

#if defined(_WIN32)

#define LITTLE_ENDIAN  1234
#define BIG_ENDIAN 4321
#define PDP_ENDIAN	3412

/*
 * Use GCC and Visual Studio compiler defines to determine endian.
 */
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define BYTE_ORDER LITTLE_ENDIAN
#else
#define BYTE_ORDER BIG_ENDIAN
#endif

#elif defined(HAVE_ENDIAN_H)
#include_next <endian.h>

#elif defined(HAVE_MACHINE_ENDIAN_H)
#include_next <machine/endian.h>

#elif defined(__sun) || defined(_AIX) || defined(__hpux)
#include <sys/types.h>
#include <arpa/nameser_compat.h>

#elif defined(__sgi)
#include <standards.h>
#include <sys/endian.h>

#endif

#ifndef __STRICT_ALIGNMENT
#define __STRICT_ALIGNMENT
#if defined(__i386)    || defined(__i386__)    || \
    defined(__x86_64)  || defined(__x86_64__)  || \
    defined(__s390__)  || defined(__s390x__)   || \
    defined(__aarch64__)                       || \
    ((defined(__arm__) || defined(__arm)) && __ARM_ARCH >= 6)
#undef __STRICT_ALIGNMENT
#endif
#endif

#endif
