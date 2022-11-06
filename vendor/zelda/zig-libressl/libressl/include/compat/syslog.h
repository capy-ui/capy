/*
 * Public domain
 * syslog.h compatibility shim
 */

#ifndef _WIN32
#include_next <syslog.h>
#endif

#ifndef LIBCRYPTOCOMPAT_SYSLOG_H
#define LIBCRYPTOCOMPAT_SYSLOG_H

#ifndef HAVE_SYSLOG_R

#include <stdarg.h>

#ifdef _WIN32
#define	LOG_INFO	6	/* informational */
#define LOG_USER    (1<<3)  /* random user-level messages */
#define	LOG_LOCAL2	(18<<3)	/* reserved for local use */
#endif

struct syslog_data {
	int log_stat;
	const char *log_tag;
	int log_fac;
	int log_mask;
};

#define SYSLOG_DATA_INIT {0, (const char *)0, LOG_USER, 0xff}

void syslog_r(int, struct syslog_data *, const char *, ...);
void vsyslog_r(int, struct syslog_data *, const char *, va_list);

#endif

#endif
