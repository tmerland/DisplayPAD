#!/usr/bin/env bash
# =============================================================================
# DisplayPAD — PoC stream test
# =============================================================================
# Sends a synthetic H.264 test stream to an iPad (or any TCP listener) via
# iproxy + ffmpeg.
#
# Usage:
#   chmod +x Scripts/test_stream.sh
#   ./Scripts/test_stream.sh
#
# Prerequisites (macOS):
#   brew install libimobiledevice   # provides iproxy
#   brew install ffmpeg
#
# The iPad must be:
#   • Connected via USB Lightning
#   • Jailbroken with Chimera / Sileo
#   • Running the DisplayPAD receiver app (listening on port 7000)
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
#  Configuration                                                               #
# --------------------------------------------------------------------------- #
LOCAL_PORT=7000
DEVICE_PORT=7000
WIDTH=1024
HEIGHT=768
FPS=30
BITRATE="2M"       # ffmpeg bitrate string
DURATION=60        # seconds; 0 = run until Ctrl+C

IPROXY_PID=""

# --------------------------------------------------------------------------- #
#  Helpers                                                                     #
# --------------------------------------------------------------------------- #
info()  { printf '\033[0;34m[DisplayPAD]\033[0m %s\n' "$*"; }
ok()    { printf '\033[0;32m[DisplayPAD]\033[0m %s\n' "$*"; }
warn()  { printf '\033[0;33m[DisplayPAD]\033[0m %s\n' "$*" >&2; }
error() { printf '\033[0;31m[DisplayPAD]\033[0m %s\n' "$*" >&2; }

cleanup() {
    info "Shutting down..."
    if [[ -n "$IPROXY_PID" ]] && kill -0 "$IPROXY_PID" 2>/dev/null; then
        kill "$IPROXY_PID" 2>/dev/null || true
        wait "$IPROXY_PID" 2>/dev/null || true
        info "iproxy (PID $IPROXY_PID) stopped."
    fi
    ok "Done."
}

trap cleanup EXIT INT TERM

# --------------------------------------------------------------------------- #
#  Dependency checks                                                           #
# --------------------------------------------------------------------------- #
info "Checking dependencies..."

if ! command -v iproxy &>/dev/null; then
    error "'iproxy' not found. Install it with:"
    error "    brew install libimobiledevice"
    exit 1
fi
ok "iproxy   : $(command -v iproxy)"

if ! command -v ffmpeg &>/dev/null; then
    error "'ffmpeg' not found. Install it with:"
    error "    brew install ffmpeg"
    exit 1
fi
ok "ffmpeg   : $(command -v ffmpeg)"

# --------------------------------------------------------------------------- #
#  Start iproxy                                                                #
# --------------------------------------------------------------------------- #
info "Starting iproxy ${LOCAL_PORT}:${DEVICE_PORT} ..."
iproxy "${LOCAL_PORT}" "${DEVICE_PORT}" &
IPROXY_PID=$!
sleep 1   # give iproxy a moment to bind

if ! kill -0 "$IPROXY_PID" 2>/dev/null; then
    error "iproxy failed to start. Is the iPad connected via USB?"
    exit 1
fi
ok "iproxy running (PID ${IPROXY_PID})"

# --------------------------------------------------------------------------- #
#  Build ffmpeg command                                                        #
# --------------------------------------------------------------------------- #
FFMPEG_OPTS=(
    -hide_banner
    -loglevel warning
    # Synthetic test source: colour bars + moving elements
    -f lavfi -i "testsrc2=size=${WIDTH}x${HEIGHT}:rate=${FPS}"
    # H.264 encoding
    -vcodec libx264
    -preset ultrafast
    -tune zerolatency
    -b:v "${BITRATE}"
    -pix_fmt yuv420p
    # Annex-B framing (startcodes) so the receiver can parse NALs
    -bsf:v h264_mp4toannexb
    # Output: raw H.264 over TCP
    -f h264
)

if [[ "${DURATION}" -gt 0 ]]; then
    FFMPEG_OPTS+=(-t "${DURATION}")
fi

FFMPEG_OPTS+=("tcp://127.0.0.1:${LOCAL_PORT}")

# --------------------------------------------------------------------------- #
#  Run                                                                         #
# --------------------------------------------------------------------------- #
info "Streaming ${WIDTH}x${HEIGHT} @ ${FPS} fps, bitrate ${BITRATE}"
info "Target : tcp://127.0.0.1:${LOCAL_PORT}  (forwarded → iPad:${DEVICE_PORT})"
[[ "${DURATION}" -gt 0 ]] && info "Duration: ${DURATION}s  (Ctrl+C to stop early)"
info "Press Ctrl+C to stop at any time."
echo ""

ffmpeg "${FFMPEG_OPTS[@]}"

ok "Stream finished."
