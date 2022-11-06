/*
 * Public domain
 * unistd.h compatibility shim
 */

#ifndef LIBCRYPTOCOMPAT_UNISTD_H
#define LIBCRYPTOCOMPAT_UNISTD_H

#ifndef _MSC_VER

#include_next <unistd.h>

#ifdef __MINGW32__
int ftruncate(int fd, off_t length);
uid_t getuid(void);
ssize_t pread(int d, void *buf, size_t nbytes, off_t offset);
ssize_t pwrite(int d, const void *buf, size_t nbytes, off_t offset);
#endif

#else

#include <stdlib.h>
#include <io.h>
#include <process.h>

#define STDOUT_FILENO   1
#define STDERR_FILENO   2

#define R_OK    4
#define W_OK    2
#define X_OK    0
#define F_OK    0

#define SEEK_SET        0
#define SEEK_CUR        1
#define SEEK_END        2

#define access _access

#ifdef _MSC_VER
#include <windows.h>
static inline unsigned int sleep(unsigned int seconds)
{
       Sleep(seconds * 1000);
       return seconds;
}
#endif

int ftruncate(int fd, off_t length);
uid_t getuid(void);
ssize_t pread(int d, void *buf, size_t nbytes, off_t offset);
ssize_t pwrite(int d, const void *buf, size_t nbytes, off_t offset);

#endif

#ifndef HAVE_GETENTROPY
int getentropy(void *buf, size_t buflen);
#else
/*
 * Solaris 11.3 adds getentropy(2), but defines the function in sys/random.h
 */
#if defined(__sun)
#include <sys/random.h>
#endif
#endif

#ifndef HAVE_GETPAGESIZE
int getpagesize(void);
#endif

#define pledge(request, paths) 0
#define unveil(path, permissions) 0

#ifndef HAVE_PIPE2
int pipe2(int fildes[2], int flags);
#endif

#endif
