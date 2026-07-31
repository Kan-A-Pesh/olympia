# @olympia/iris-hub

The hub daemon. Owns the hardware: serial ports, the MQTT client, the encoders and the
directional pad, and the Chromium kiosk that displays the tiles.

Devices reach it over two transports that converge on one driver interface — USB CDC for
the oscilloscope, MQTT for everything else. A USB device is displayed locally and
republished on the bus, so the hub keeps working when the network does not.

Runs on a Raspberry Pi 4 with a read-only root filesystem. See `docs/05-runtime.md`.
