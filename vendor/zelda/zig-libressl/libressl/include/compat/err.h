/*
 * Public domain
 * err.h compatibility shim
 */

#ifdef HAVE_ERR_H

#include_next <err.h>

#else

#ifndef LIBCRYPTOCOMPAT_ERR_H
#define LIBCRYPTOCOMPAT_ERR_H

#include <errno.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#if defined(_MSC_VER)
__declspec(noreturn)
#else
__attribute__((noreturn))
#endif
static inline void
err(int eval, const char *fmt, ...)
{
	int sverrno = errno;
	va_list ap;

	va_start(ap, fmt);
	if (fmt != NULL) {
		vfprintf(stderr, fmt, ap);
		fprintf(stderr, ": ");
	}
	va_end(ap);
	fprintf(stderr, "%s\n", strerror(sverrno));
	exit(eval);
}

#if defined(_MSC_VER)
__declspec(noreturn)
#else
__attribute__((noreturn))
#endif
static inline void
errx(int eval, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	if (fmt != NULL)
		vfprintf(stderr, fmt, ap);
	va_end(ap);
	fprintf(stderr, "\n");
	exit(eval);
}

static inline void
warn(const char *fmt, ...)
{
	int sverrno = errno;
	va_list ap;

	va_start(ap, fmt);
	if (fmt != NULL) {
		vfprintf(stderr, fmt, ap);
		fprintf(stderr, ": ");
	}
	va_end(ap);
	fprintf(stderr, "%s\n", strerror(sverrno));
}

static inline void
vwarnx(const char *fmt, va_list args)
{
	if (fmt != NULL)
		vfprintf(stderr, fmt, args);
	fprintf(stderr, "\n");
}

static inline void
warnx(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vwarnx(fmt, ap);
	va_end(ap);
}

#endif

#endif
