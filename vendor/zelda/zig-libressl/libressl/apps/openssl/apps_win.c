/*
 * Public domain
 *
 * Dongsheng Song <dongsheng.song@gmail.com>
 * Brent Cook <bcook@openbsd.org>
 */

#include <windows.h>

#include <io.h>
#include <fcntl.h>

#include "apps.h"

double
app_timer_real(int get)
{
	static __int64 start;
	__int64 now;

	now = GetTickCount64();
	if (get) {
		return (now - start) / 1000.0;
	}
	start = now;
	return 0.0;
}

double
app_timer_user(int stop)
{
	static unsigned __int64 tmstart;
	union {
		unsigned __int64 u64;
		FILETIME ft;
	} ct, et, kt, ut;

	GetProcessTimes(GetCurrentProcess(), &ct.ft, &et.ft, &kt.ft, &ut.ft);
	if (stop)
		return (ut.u64 + kt.u64 - tmstart) / (double) 10000000;

	tmstart = ut.u64 + kt.u64;
	return 0.0;
}

int
setup_ui(void)
{
	ui_method = UI_create_method("OpenSSL application user interface");
	UI_method_set_opener(ui_method, ui_open);
	UI_method_set_reader(ui_method, ui_read);
	UI_method_set_writer(ui_method, ui_write);
	UI_method_set_closer(ui_method, ui_close);

	/*
	 * Set STDIO to binary
	 */
	_setmode(_fileno(stdin), _O_BINARY);
	_setmode(_fileno(stdout), _O_BINARY);
	_setmode(_fileno(stderr), _O_BINARY);

	return 0;
}

void
destroy_ui(void)
{
	if (ui_method) {
		UI_destroy_method(ui_method);
		ui_method = NULL;
	}
}

static void (*speed_alarm_handler)(int);
static HANDLE speed_thread;
static unsigned int speed_lapse;
static volatile unsigned int speed_schlock;

void
speed_signal(int sigcatch, void (*func)(int sigraised))
{
	speed_alarm_handler = func;
}

static DWORD WINAPI
speed_timer(VOID * arg)
{
	speed_schlock = 1;
	Sleep(speed_lapse);
	(*speed_alarm_handler)(0);
	return (0);
}

unsigned int
speed_alarm(unsigned int seconds)
{
	DWORD err;

	speed_lapse = seconds * 1000;
	speed_schlock = 0;

	speed_thread = CreateThread(NULL, 4096, speed_timer, NULL, 0, NULL);
	if (speed_thread == NULL) {
		err = GetLastError();
		BIO_printf(bio_err, "CreateThread failed (%lu)", err);
		ExitProcess(err);
	}

	while (!speed_schlock)
		Sleep(0);

	return (seconds);
}

void
speed_alarm_free(int run)
{
	DWORD err;

	if (run) {
		if (TerminateThread(speed_thread, 0) == 0) {
			err = GetLastError();
			BIO_printf(bio_err, "TerminateThread failed (%lu)",
			    err);
			ExitProcess(err);
		}
	}

	if (CloseHandle(speed_thread) == 0) {
		err = GetLastError();
		BIO_printf(bio_err, "CloseHandle failed (%lu)", err);
		ExitProcess(err);
	}

	speed_thread = NULL;
	speed_lapse = 0;
	speed_schlock = 0;
}
