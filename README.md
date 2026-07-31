# Olympia

Olympia is an instrument hub for home-built test equipment.

Devices publish what they measure — an oscilloscope over USB, sensors over MQTT — and the
hub arranges them as tiles on a screen. The hub knows nothing about any particular device:
each one announces its streams and its controls when it connects, and is laid out
accordingly.

**Current status:** Early development. The message protocol and parts of the hub daemon
are written. No device firmware is finished yet.

## Layout

- `apps/helios-server` — MQTT broker, device registry, admission panel
- `apps/iris-hub` — hub daemon: serial and MQTT transports, encoders, kiosk display
- `packages/hermes-protocol` — shared message contract
- `packages/tiles-ui` — tile layout and widgets
- `firmware/` — device firmware
- `hardware/` — device tree overlays and printed enclosures

## Building

```sh
pnpm install
pnpm build
pnpm test
```

Requires Node 22 and pnpm 9.

## Hardware

- Raspberry Pi 4 Model B (2 GB), driving a salvaged ThinkPad T470 panel over eDP
- Four EC11 rotary encoders and an eight-way directional pad, read through the kernel
  `rotary-encoder` and `gpio-keys` drivers
- Raspberry Pi Pico running [sigrok-pico](https://github.com/pico-coder/sigrok-pico),
  connected over USB
- ESP32 nodes over MQTT, authenticated by pinned self-signed certificates

## License

Apache 2.0 for software and firmware, Creative Commons Attribution 4.0 for the mechanical
and electronic designs. See [LICENSE](LICENSE).
