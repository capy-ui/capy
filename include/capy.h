#ifndef _CAPY_HEADER
#define _CAPY_HEADER

typedef void* CapyWidget;
typedef void* CapyWindow;

int capy_init_backend(void);

void capy_run_event_loop(void);

// window
CapyWindow capy_window_init(void);

void capy_window_show(CapyWindow window);

void capy_window_close(CapyWindow window);

void capy_window_resize(CapyWindow window, unsigned int width, unsigned int height);

void capy_window_set(CapyWindow window, CapyWidget widget);

CapyWidget capy_window_get_child(CapyWindow window);

// button
CapyWidget capy_button(const char* label);

#endif
