// TCPReceiver.h — Réception TCP du flux H.264 depuis le Mac

#import <Foundation/Foundation.h>

// ─── Protocole binaire DisplayPAD ───────────────────────────────────────────

#define DP_MAGIC         0x44505044   // "DPPD" big-endian
#define DP_VERSION_MAJOR 0
#define DP_VERSION_MINOR 1

// Types de paquets
typedef NS_ENUM(uint32_t, DPPacketType) {
    DPPacketTypeHELLO        = 1,
    DPPacketTypeHELLO_ACK    = 2,
    DPPacketTypeCONFIG       = 3,
    DPPacketTypeCONFIG_ACK   = 4,
    DPPacketTypeFRAME        = 5,
    DPPacketTypePING         = 6,
    DPPacketTypePONG         = 7,
    DPPacketTypeDISCONNECT   = 8,
};

// En-tête de paquet (big-endian sur le réseau)
typedef struct __attribute__((packed)) {
    uint32_t magic;    // Doit valoir DP_MAGIC (big-endian)
    uint32_t type;     // DPPacketType (big-endian)
    uint32_t length;   // Longueur du payload en bytes (big-endian)
} DPHeader;

// Payload CONFIG : paramètres de flux vidéo
typedef struct __attribute__((packed)) {
    uint32_t width;        // Largeur en pixels (big-endian)
    uint32_t height;       // Hauteur en pixels (big-endian)
    uint32_t fps;          // Images par seconde (big-endian)
    uint32_t bitrate;      // Débit cible en bps (big-endian)
    uint32_t orientation;  // 0 = paysage, 1 = portrait (big-endian)
} DPConfigPayload;

// Payload HELLO : identification de l'émetteur
typedef struct __attribute__((packed)) {
    uint8_t  version_major;   // Numéro de version majeur
    uint8_t  version_minor;   // Numéro de version mineur
    char     device_name[64]; // Nom du device (null-terminé)
} DPHelloPayload;

// ─── Protocole délégué ──────────────────────────────────────────────────────

@class TCPReceiver;

@protocol TCPReceiverDelegate <NSObject>

/// Appelé quand une connexion est établie avec le Mac
- (void)tcpReceiverDidConnect:(TCPReceiver *)receiver;

/// Appelé quand la connexion est fermée (normalement ou en erreur)
- (void)tcpReceiverDidDisconnect:(TCPReceiver *)receiver;

/// Appelé à réception d'une frame H.264 (NAL units brutes)
- (void)tcpReceiver:(TCPReceiver *)receiver didReceiveFrame:(NSData *)nalData;

/// Appelé à réception d'un paquet CONFIG (paramètres vidéo)
- (void)tcpReceiver:(TCPReceiver *)receiver didReceiveConfig:(DPConfigPayload)config;

@end

// ─── Interface TCPReceiver ───────────────────────────────────────────────────

@interface TCPReceiver : NSObject

/// Port d'écoute (défaut : 7000)
@property (nonatomic, assign) uint16_t port;

/// Délégué recevant les événements de connexion et les frames
@property (nonatomic, weak) id<TCPReceiverDelegate> delegate;

/// Indique si le récepteur écoute actuellement
@property (nonatomic, readonly) BOOL isListening;

/// Démarre l'écoute sur le port configuré (bloque jusqu'à la première connexion sur un thread séparé)
- (void)startListening;

/// Arrête l'écoute et ferme les sockets ouverts
- (void)stopListening;

@end
