#!/usr/bin/env python3
import threading
import time

import app
from capture_worker import CaptureWorker
from okam_native.bridge import QuietThreadingHTTPServer, make_handler


def main() -> None:
    server = QuietThreadingHTTPServer(
        ("0.0.0.0", app.PORT),
        make_handler(app.status_provider, app.bridge_provider),
    )
    threading.Thread(target=server.serve_forever, daemon=True).start()
    app.configure()
    worker = CaptureWorker(
        session=app.SESSION,
        ffmpeg=app.FFMPEG,
        state_callback=app.set_state,
    )
    worker.start()
    if app.PROBE_ON_START:
        threading.Thread(target=app.probe_camera, daemon=True).start()
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        pass
    finally:
        worker.stop()
        if app.SESSION is not None:
            app.SESSION.close()
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
