#ifndef _ZGT_HEADER
#define _ZGT_HEADER

typedef void* ZgtWidget;
typedef void* ZgtWindow;

int zgt_init_backend();

void zgt_run_event_loop();

// window
ZgtWindow zgt_window_init();

void zgt_window_show(ZgtWindow window);

void zgt_window_close(ZgtWindow window);

void zgt_window_resize(ZgtWindow window, unsigned int width, unsigned int height);

void zgt_window_set(ZgtWindow window, ZgtWidget widget);

ZgtWidget zgt_window_get_child(ZgtWindow window);

// button
ZgtWidget zgt_button(const char* label);

#endif
