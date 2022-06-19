#include <stdio.h>
#include <zgt.h>

void main() {
	zgt_init_backend();

	ZgtWindow window = zgt_window_init();
	zgt_window_show(window);

	zgt_run_event_loop();
}
