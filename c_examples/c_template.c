#include <stdio.h>
#include <capy.h>

void main() {
	CapyWindow window;
	CapyWidget button;
	capy_init();

	window = capy_window_init();
	capy_window_set_preferred_size(window, 800, 600);

	button = capy_button_new();
	capy_button_set_label(button, "Hello, World");
	capy_window_set(window, button);

	capy_window_show(window);

	capy_run_event_loop();
}
