# DisplayPAD

![Version](https://img.shields.io/badge/version-v0.1.0-blue) ![Platform Mac](https://img.shields.io/badge/platform-macOS-lightgrey) ![Platform iPad](https://img.shields.io/badge/platform-iOS%2012.5-lightgrey) ![License](https://img.shields.io/badge/license-MIT-green)

> **Turn a jailbroken iPad Air into a wired USB second display — for free.**
> DisplayPAD is an open-source alternative to Duet Display that uses a Lightning cable and your existing USB stack instead of a paid subscription.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Installation — Mac](#installation--mac)
- [Installation — iPad](#installation--ipad)
- [Build](#build)
- [Test PoC](#test-poc)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

| Component | Stack | Notes |
|-----------|-------|-------|
| **Mac app** | Swift / SwiftUI | Menu-bar app; captures the display, encodes H.264, pushes frames over USB |
| **iPad app** | Objective-C / Theos | Cydia/Sileo `.deb`; receives frames, decodes with VideoToolbox, renders full-screen |
| **Transport** | `usbmuxd` → TCP port 7000 | No Wi-Fi needed; `iproxy` tunnels the connection over Lightning |
| **Codec** | H.264 Annex-B | Hardware encode on Mac (VideoToolbox), hardware decode on iPad |

---

## Architecture

```
MacBook Pro                                   iPad Air (jailbroken)
┌──────────────────────────────┐  USB / Lightning  ┌──────────────────────────────┐
│  DisplayPADMac (menu-bar)    │                   │  DisplayPAD.app (Theos .deb) │
│                              │                   │                              │
│  ┌────────────────┐          │                   │  ┌────────────────┐          │
│  │ Screen capture │          │                   │  │ VideoToolbox   │          │
│  │ (ScreenCaptureKit)        │                   │  │ H.264 decoder  │          │
│  └───────┬────────┘          │                   │  └───────┬────────┘          │
│          │ CMSampleBuffer    │                   │          │ CVPixelBuffer      │
│  ┌───────▼────────┐          │                   │  ┌───────▼────────┘          │
│  │ VideoToolbox   │          │                   │  │ CALayer / OpenGL ES        │
│  │ H.264 encoder  │          │                   │  │ full-screen renderer        │
│  └───────┬────────┘          │                   │  └────────────────────────────│
│          │ H.264 Annex-B     │   DP protocol     │          ▲                   │
│  ┌───────▼────────┐          │  ──────────────►  │  ┌───────┴────────┐          │
│  │ TCP socket     │          │  TCP :7000        │  │ TCP socket     │          │
│  │ (DPHeader +   │          │◄──────────────    │  │ (DPHeader +   │          │
│  │  payload)      │          │   HELLO / CONFIG  │  │  payload)      │          │
│  └────────────────┘          │                   │  └────────────────┘          │
│                              │                   │                              │
│         iproxy 7000:7000     │◄─────────────────►│        usbmuxd              │
└──────────────────────────────┘    usbmuxd/USB    └──────────────────────────────┘
```

**Binary protocol** (`Shared/Protocol.h`):
```
[ DPHeader (12 bytes) ][ payload (0…N bytes) ]
  magic=0x44505044 "DPPD"
  type = HELLO | HELLO_ACK | CONFIG | CONFIG_ACK | FRAME | PING | PONG | DISCONNECT
  length = payload byte count (0 for control packets)
```
All integers are big-endian (network byte order).

---

## Installation — Mac

### Prerequisites

```bash
# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# libimobiledevice (provides iproxy, ideviceinfo…)
brew install libimobiledevice

# Xcode (from the App Store) — required to build & run the Mac app
```

### Trust the iPad

Connect the iPad via Lightning, unlock it and tap **Trust** when prompted.  
Verify detection:

```bash
ideviceinfo -u $(ideviceinfo -l | head -1) | grep DeviceName
```

---

## Installation — iPad

### Prerequisites

| Requirement | Details |
|-------------|---------|
| iPad Air 1 | A1474 / A1475 / A1476 |
| iOS version | 12.5.7 or 12.5.8 |
| Jailbreak | [Chimera](https://chimera.coolstar.org/) (unc0ver also works) |
| Package manager | [Sileo](https://getsileo.app/) |
| Theos dependencies | `apt install theos` via Sileo (BigBoss repo) |

### Install the .deb

Once built (see [Build](#build)):

```bash
# Copy to iPad
scp iPad/build/displaypad_0.1_iphoneos-arm.deb root@<iPad-IP>:/tmp/

# SSH into iPad and install
ssh root@<iPad-IP>
dpkg -i /tmp/displaypad_0.1_iphoneos-arm.deb
uicache          # refresh SpringBoard
```

Or install via Sileo by sideloading the `.deb` directly.

---

## Build

### Mac app

```bash
cd Mac/DisplayPADMac
open DisplayPADMac.xcodeproj   # then ⌘B to build, ⌘R to run
```

Requires **Xcode 15+**, target **macOS 13+**.

### iPad app (Theos)

```bash
# Install Theos on macOS (cross-compile for arm)
export THEOS=~/theos
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"

cd iPad
make package   # produces layout/*.deb
make install   # scp + dpkg if THEOS_DEVICE_IP is set
```

Set `THEOS_DEVICE_IP` and `THEOS_DEVICE_PORT` in your environment to point at the iPad's SSH server.

---

## Test PoC

The `Scripts/test_stream.sh` script lets you verify the entire USB + ffmpeg pipeline **without** building either app:

```bash
# Make executable (once)
chmod +x Scripts/test_stream.sh

# Run (iPad must be connected via USB)
./Scripts/test_stream.sh
```

What it does:
1. Verifies `iproxy` and `ffmpeg` are installed.
2. Launches `iproxy 7000:7000` to tunnel USB → TCP.
3. Streams a synthetic `testsrc2` H.264 feed (1024×768 @ 30 fps) to `localhost:7000`.
4. Cleans up `iproxy` on exit (Ctrl+C safe).

On the iPad side, any TCP listener on port 7000 (e.g. `nc -l 7000 > /tmp/stream.h264`) can capture the raw stream.

---

## Roadmap

| Milestone | Description | Status |
|-----------|-------------|--------|
| **v0.1 — PoC** | Folder structure, shared protocol header, test stream script | 🟡 In progress |
| **v0.2 — Mac sender** | SwiftUI menu-bar app, screen capture via ScreenCaptureKit, H.264 encoding, TCP send with DP protocol | ⬜ Planned |
| **v0.3 — Virtual screen** | Register a virtual display on macOS so the iPad appears as a real external monitor | ⬜ Planned |
| **v0.4 — Full protocol** | iPad Theos receiver, VideoToolbox decode, full-screen renderer, HELLO/CONFIG handshake | ⬜ Planned |
| **v1.0 — Release** | Stability, auto-reconnect, Sileo package, notarised Mac app, public release | ⬜ Planned |
| **v2.0 — Touch input** | Forward iPad touch events back to Mac as HID pointer/keyboard events | ⬜ Planned |

---

## Contributing

Contributions are welcome!

1. Fork the repository.
2. Create a feature branch: `git checkout -b feat/my-feature`.
3. Commit your changes: `git commit -m "feat: my feature"`.
4. Push and open a Pull Request.

Please follow the existing code style and add tests where applicable.  
For major changes, open an issue first to discuss the approach.

---

## License

This project is licensed under the **MIT License**.

```
MIT License

Copyright (c) 2026 DisplayPAD Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
