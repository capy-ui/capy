/*
 * Public domain
 *
 * Kinichiro Inoguchi <inoguchi@openbsd.org>
 */

#ifdef _WIN32

#define NO_REDEF_POSIX_FUNCTIONS

#include <unistd.h>

ssize_t
pwrite(int d, const void *buf, size_t nbytes, off_t offset)
{
	off_t cpos, opos, rpos;
	ssize_t bytes;
	if((cpos = lseek(d, 0, SEEK_CUR)) == -1)
		return -1;
	if((opos = lseek(d, offset, SEEK_SET)) == -1)
		return -1;
	if((bytes = write(d, buf, nbytes)) == -1)
		return -1;
	if((rpos = lseek(d, cpos, SEEK_SET)) == -1)
		return -1;
	return bytes;
}

#endif
