# DisplayPAD v0.2.0 — iPad Settings, Zoom & Experimental Wireless 🎉

> **Turn your jailbroken iPad into a wired USB second display for Mac — free, open-source, and low latency.**

---

## ⚠️ Performance & Hardware Disclaimer

> [!WARNING]
> **Read before installing — especially on older iPads (iPad Air 1 / Apple A7):**
> - **Wired USB (`usbmuxd`) is strongly recommended**: The Lightning/USB connection provides near-zero latency, rock-solid 60 FPS streaming, and charges your iPad simultaneously.
> - **Legacy Hardware Limits**: On 2013 Apple A7 devices, decoding full Retina `2048×1536 @ 60 fps` pushes the hardware H.264 decoder to its maximum capacity. If you experience frame drops or delay, switch to **`1366×1024 @ 30 fps`** (or `1024×768 HiDPI`) in the Mac menu bar app for smoother performance and larger, easier-to-read text.
> - **Wireless Mode (Wi-Fi IP / AWDL Direct) is Experimental**: While Wi-Fi and Apple Peer-to-Peer (`awdl0`) discovery are included in this release, older 802.11n Wi-Fi radios and shared networks introduce significant jitter and latency compared to wired USB.

---

## ✨ What's New in v0.2.0

- **3-Finger Settings Menu on iPad**: Tap anywhere on the screen with **3 fingers** to open a translucent settings HUD (`SettingsOverlayView`) with:
  - Live telemetry (FPS, active resolution, connection status)
  - Video scaling mode switcher (`Aspect Fit` / `Aspect Fill`)
  - Current zoom level & one-tap reset
  - Local Wi-Fi IP address readout & manual stream reset
- **Interactive Zoom & Pan (2 Fingers)**:
  - **Pinch (2 fingers)** to zoom smoothly from `1.0x` to `5.0x` — great for reading small macOS text on Retina screens.
  - **Drag (2 fingers)** to pan around the zoomed display.
  - **Double-tap (2 fingers)** to instantly reset zoom back to `1:1`.
- **Low-Latency Pipeline Optimizations**:
  - `TCP_NODELAY` enabled on both Mac and iPad sockets.
  - `SCStreamConfiguration.queueDepth = 2` and `MaxFrameDelayCount = 0` (zero encoder/capture frame buffering).
  - Active send backpressure (`inFlightFrames` check) to prevent bufferbloat before H.264 encoding.
- **Experimental Wireless Modes (Wi-Fi IP & AWDL Direct)**:
  - Dual-stack IPv4/IPv6 sockets + Bonjour `_displaypad._tcp` (`includesPeerToPeer = YES`) on iPad and `NWBrowser` on Mac.

---

## 📦 Downloads & Artifacts

| Platform | File | Description |
|---|---|---|
| **macOS** | [`DisplayPADMac-v0.2.0.dmg`](DisplayPADMac-v0.2.0.dmg) | Disk image installer for Mac (drag & drop to `/Applications`) |
| **macOS** | [`DisplayPADMac-v0.2.0.zip`](DisplayPADMac-v0.2.0.zip) | Portable `.app` archive |
| **iPadOS** | [`com.displaypad.ipad_0.2.0_iphoneos-arm.deb`](com.displaypad.ipad_0.2.0_iphoneos-arm.deb) | Debian package for Sileo, Zebra, Cydia, or Filza |

---

## 🔒 Verification & Checksums (SHA-256)

```text
dafdc8c2ff299880ae0ad7e47de62244df2ac372382fc7a757843139cdd462dc  DisplayPADMac-v0.2.0.dmg
98fe7704dbf46e867f64e04a698f2ab28c879e1c5d1aef94623afd27db40cdf4  DisplayPADMac-v0.2.0.zip
b18c851f59965366a0ceda172306c42074bbab39e836cfeec671541da7462669  com.displaypad.ipad_0.2.0_iphoneos-arm.deb
```
