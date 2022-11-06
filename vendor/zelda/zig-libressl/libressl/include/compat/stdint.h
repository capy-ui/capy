/*
 * Public domain
 * stdint.h compatibility shim
 */

#ifdef _MSC_VER
#include <../include/stdint.h>
#else
#include_next <stdint.h>
#endif

#ifndef LIBCRYPTOCOMPAT_STDINT_H
#define LIBCRYPTOCOMPAT_STDINT_H

#ifndef SIZE_MAX
#include <limits.h>
#endif

#endif
