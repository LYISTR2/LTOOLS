# Third-Party Notice

This directory contains a modified local snapshot of:

- Project: `Eric86777/vps-tcp-tune`
- Upstream core file: `net-tcp-tune.sh`
- Imported upstream blob SHA: `2d891bec01e24f64a9f6fdc5d6faa95378c6d537`
- Imported Snell patch blob SHA: `0a89e13d7db4d39c8280a26bdc312dd73a8b0db4`
- License: MIT
- Copyright: Copyright (c) 2025 Eric Reed

Local modifications:

1. Added `--action <number>` for one-shot local feature dispatch.
2. Added category entry scripts that call the repository-local shared core.
3. Replaced the generated service documentation URL with the local LTOOLS path.
4. Replaced the Snell patch's online usage example with a local path.

The upstream name remains in two regular expressions solely to remove legacy shell aliases that downloaded old online versions. Those expressions do not perform network requests.
