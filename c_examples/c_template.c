#include <stdio.h>
#include <capy.h>

void main() {
	CapyWindow window;
	CapyWidget button;
	capy_init_backend();

	window = capy_window_init();
	capy_window_resize(window, 800, 600);

	button = capy_button("Hello, World");
	capy_window_set(window, button);

	capy_window_show(window);

	capy_run_event_loop();
}
