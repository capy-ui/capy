#include <stdio.h>
#include <zgt.h>

void main() {
	ZgtWindow window;
	ZgtWidget button;
	zgt_init_backend();

	window = zgt_window_init();
	zgt_window_resize(window, 800, 600);

	button = zgt_button("Hello, World");
	zgt_window_set(window, button);

	zgt_window_show(window);

	zgt_run_event_loop();
}
