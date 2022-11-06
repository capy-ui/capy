/*
 * Public domain
 *
 * Kinichiro Inoguchi <inoguchi@openbsd.org>
 */

#ifdef _WIN32

#include <unistd.h>

int
ftruncate(int fd, off_t length)
{
	return _chsize(fd, length);
}

#endif
