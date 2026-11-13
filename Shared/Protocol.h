/*
 * DisplayPAD — Shared Binary Protocol
 * Mac ↔ iPad over USB (usbmuxd / TCP port 7000)
 *
 * All multi-byte integers are transmitted in network byte order (big-endian).
 * Use htonl() / ntohl() when writing / reading on both platforms.
 *
 * Version: DP_VERSION_MAJOR.DP_VERSION_MINOR
 */

#ifndef DISPLAYPAD_PROTOCOL_H
#define DISPLAYPAD_PROTOCOL_H

#include <stdint.h>

/* ------------------------------------------------------------------ */
/*  Version                                                            */
/* ------------------------------------------------------------------ */
#define DP_VERSION_MAJOR  0
#define DP_VERSION_MINOR  1

/* ------------------------------------------------------------------ */
/*  Magic                                                              */
/* ------------------------------------------------------------------ */
/* ASCII "DPPD" = 0x44 0x50 0x50 0x44                                 */
#define DP_MAGIC  0x44505044u

/* ------------------------------------------------------------------ */
/*  Packet types                                                       */
/* ------------------------------------------------------------------ */
#define DP_TYPE_HELLO       0x01u   /* Mac → iPad: introduce ourselves  */
#define DP_TYPE_HELLO_ACK   0x02u   /* iPad → Mac: accept / reject      */
#define DP_TYPE_CONFIG      0x03u   /* Mac → iPad: stream parameters    */
#define DP_TYPE_CONFIG_ACK  0x04u   /* iPad → Mac: config accepted      */
#define DP_TYPE_FRAME       0x05u   /* Mac → iPad: H.264 NAL unit       */
#define DP_TYPE_PING        0x06u   /* either direction: keepalive ping */
#define DP_TYPE_PONG        0x07u   /* reply to PING                    */
#define DP_TYPE_DISCONNECT  0x08u   /* graceful teardown                */

/* ------------------------------------------------------------------ */
/*  Orientation constants (used in DPConfigPayload.orientation)        */
/* ------------------------------------------------------------------ */
#define DP_ORIENTATION_LANDSCAPE  0u
#define DP_ORIENTATION_PORTRAIT   1u

/* ------------------------------------------------------------------ */
/*  Structures                                                         */
/* ------------------------------------------------------------------ */

/**
 * DPHeader — prepended to every packet.
 *
 * Fields (all big-endian / network order):
 *   magic   — must equal DP_MAGIC; drop packet otherwise.
 *   type    — one of DP_TYPE_* above.
 *   length  — byte length of the payload that follows the header.
 *             0 for packets with no payload (PING, PONG, DISCONNECT, CONFIG_ACK).
 */
typedef struct {
    uint32_t magic;    /* 0x44505044 "DPPD" */
    uint32_t type;     /* DP_TYPE_*          */
    uint32_t length;   /* payload length     */
} __attribute__((packed)) DPHeader;

/**
 * DPHelloPayload — payload for DP_TYPE_HELLO / DP_TYPE_HELLO_ACK.
 *
 * The receiver MUST check version_major; reject if it differs from its own.
 * device_name is UTF-8, NUL-terminated, padded with NUL bytes.
 */
typedef struct {
    uint8_t version_major;    /* DP_VERSION_MAJOR                 */
    uint8_t version_minor;    /* DP_VERSION_MINOR                 */
    char    device_name[64];  /* human-readable name, NUL-padded  */
} __attribute__((packed)) DPHelloPayload;

/**
 * DPConfigPayload — payload for DP_TYPE_CONFIG.
 *
 * All uint32_t fields are big-endian.
 *   width, height  — frame dimensions in pixels.
 *   fps            — target frames per second (e.g. 30 or 60).
 *   bitrate        — target video bitrate in bits per second.
 *   orientation    — DP_ORIENTATION_LANDSCAPE or DP_ORIENTATION_PORTRAIT.
 */
typedef struct {
    uint32_t width;        /* frame width  in px (network order) */
    uint32_t height;       /* frame height in px (network order) */
    uint32_t fps;          /* frames per second   (network order) */
    uint32_t bitrate;      /* bits per second     (network order) */
    uint32_t orientation;  /* DP_ORIENTATION_*    (network order) */
} __attribute__((packed)) DPConfigPayload;

/*
 * DP_TYPE_FRAME payload:
 *   Raw H.264 Annex-B NAL unit(s).  DPHeader.length gives the total byte
 *   count.  No additional framing struct is defined; read exactly
 *   header.length bytes after the header.
 *
 * DP_TYPE_PING, DP_TYPE_PONG, DP_TYPE_DISCONNECT, DP_TYPE_CONFIG_ACK:
 *   No payload.  DPHeader.length == 0.
 */

#endif /* DISPLAYPAD_PROTOCOL_H */
