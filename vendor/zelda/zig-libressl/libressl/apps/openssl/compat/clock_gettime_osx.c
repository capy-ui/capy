#include <time.h>

#include <mach/mach_time.h>
#define ORWL_NANO (+1.0E-9)
#define ORWL_GIGA UINT64_C(1000000000)

int
clock_gettime(clockid_t clock_id, struct timespec *tp)
{
	static double orwl_timebase = 0.0;
	static uint64_t orwl_timestart = 0;

	if (!orwl_timestart) {
		mach_timebase_info_data_t tb = { 0 };
		mach_timebase_info(&tb);
		orwl_timebase = tb.numer;
		orwl_timebase /= tb.denom;
		orwl_timestart = mach_absolute_time();
	}

	double diff = (mach_absolute_time() - orwl_timestart) * orwl_timebase;
	tp->tv_sec = diff * ORWL_NANO;
	tp->tv_nsec = diff - (tp->tv_sec * ORWL_GIGA);

	return 0;
}
