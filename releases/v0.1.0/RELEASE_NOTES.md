# DisplayPAD v0.1.0 — Initial Release 🎉

> **Turn your jailbroken iPad into a wired USB second display for Mac — free, open-source and ultra low latency.**

---

## ✨ Features

- **Lightning / USB Fast Pipe**: No Wi-Fi required, no latency, zero network interference via `usbmuxd`.
- **Hardware-Accelerated H.264**: Real-time encode on macOS (VideoToolbox / ScreenCaptureKit) & decode on iOS (VideoToolbox / `AVSampleBufferDisplayLayer`).
- **HiDPI Retina Virtual Screen**: Creates a native 2048×1536 Retina virtual monitor on macOS (`CGVirtualDisplay`), visible in *System Settings > Displays*.
- **Mouse Cursor Composition**: Mac hardware cursor smoothly captured and rendered on the iPad.
- **Reactive Auto-Reconnect**: Automatic handshake detection — open the app on your iPad and streaming resumes in under 2 seconds.
- **Menu Bar Companion**: Real-time FPS, bitrate, and ping latency counters with resolution presets.
- **Native iOS Bundle**: Sileo and Cydia compatible package with full asset branding and icon support.

---

## 📦 Downloads & Artifacts

| Platform | File | Description |
|---|---|---|
| **macOS** | [`DisplayPADMac-v0.1.0.dmg`](DisplayPADMac-v0.1.0.dmg) | Disk image installer for Mac (drag & drop to `/Applications`) |
| **macOS** | [`DisplayPADMac-v0.1.0.zip`](DisplayPADMac-v0.1.0.zip) | Portable `.app` archive |
| **iPadOS** | [`com.displaypad.ipad_0.1.0_iphoneos-arm.deb`](com.displaypad.ipad_0.1.0_iphoneos-arm.deb) | Debian package for Sileo, Zebra, Cydia or Filza |

---

## 🚀 Installation Guide

### On iPad (Jailbroken)

1. Download `com.displaypad.ipad_0.1.0_iphoneos-arm.deb`.
2. Open with **Sileo** (or **Filza File Manager**) and tap **Install**.
3. Tap the **DisplayPAD** icon on your home screen.

*Alternative via SSH / Terminal:*
```bash
scp com.displaypad.ipad_0.1.0_iphoneos-arm.deb root@<IPAD_IP>:/tmp/
ssh root@<IPAD_IP> "dpkg -i /tmp/com.displaypad.ipad_0.1.0_iphoneos-arm.deb && uicache -a"
```

### On Mac

1. Open `DisplayPADMac-v0.1.0.dmg` and drag `DisplayPADMac.app` into `Applications`.
2. Ensure `libimobiledevice` is installed for USB tunneling:
   ```bash
   brew install libimobiledevice
   ```
3. Run the USB proxy (or let DisplayPAD launch it):
   ```bash
   iproxy 7100:7000 &
   ```
4. Open **DisplayPADMac**. On first launch, grant **Screen Recording** access in *System Settings > Privacy & Security > Screen & System Audio Recording*.

---

## 🔒 Verification & Checksums (SHA-256)

```text
1d45c6ca2b62259b31a7a90f5fee0ba5d52d0d2a0d4d902eacad116abc357624  DisplayPADMac-v0.1.0.dmg
700ec97ac984fa9963b3c181b61909085f46cc1115335a2c1b1b0fd287f265dc  DisplayPADMac-v0.1.0.zip
0412024f3af3975c69638c48c398f6b7353b9ab691aca4dd66212194eb229f11  com.displaypad.ipad_0.1.0_iphoneos-arm.deb
```
