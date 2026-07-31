# @olympia/hermes-protocol

The message contract shared by every Olympia component: device identity, stream and
control descriptors, topic construction, and the binary waveform codec.

This package is the source of truth. `docs/01-hermes-protocol.md` explains it, it does not
define it.

It must stay importable from both the hub daemon and the browser, so it depends on nothing
but `zod` and contains no Node built-ins.
