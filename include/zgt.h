#ifndef _ZGT_HEADER
#define _ZGT_HEADER

typedef void* ZgtWindow;

int zgt_init_backend();
ZgtWindow zgt_window_init();
void zgt_window_show(ZgtWindow window);

void zgt_run_event_loop();

#endif
