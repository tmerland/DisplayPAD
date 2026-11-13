// TCPReceiver.m — Implémentation de la réception TCP DisplayPAD

#import "TCPReceiver.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>

@interface TCPReceiver ()
@property (nonatomic, assign) int serverSocket;   // Socket d'écoute serveur
@property (nonatomic, assign) int clientSocket;   // Socket client connecté
@property (nonatomic, assign) BOOL isListening;
@property (nonatomic, assign) BOOL shouldStop;
@end

@implementation TCPReceiver

- (instancetype)init {
    self = [super init];
    if (self) {
        _port          = 7000;
        _serverSocket  = -1;
        _clientSocket  = -1;
        _isListening   = NO;
        _shouldStop    = NO;
    }
    return self;
}

- (void)dealloc {
    [self stopListening];
}

// ─── Lecture robuste : lit exactement `length` bytes depuis un fd ────────────
/// Retourne YES si tous les bytes ont été lus, NO en cas d'erreur ou de déconnexion.
- (BOOL)readExactly:(size_t)length intoBuffer:(uint8_t *)buffer fromSocket:(int)sock {
    size_t totalRead = 0;
    while (totalRead < length) {
        if (self.shouldStop) return NO;

        ssize_t n = recv(sock, buffer + totalRead, length - totalRead, 0);
        if (n > 0) {
            totalRead += (size_t)n;
        } else if (n == 0) {
            // Connexion fermée proprement par le pair
            NSLog(@"[TCPReceiver] Connexion fermée par le pair");
            return NO;
        } else {
            // Erreur
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                // Interruption temporaire — réessayer
                continue;
            }
            NSLog(@"[TCPReceiver] Erreur recv : %s (errno=%d)", strerror(errno), errno);
            return NO;
        }
    }
    return YES;
}

// ─── Envoi d'un paquet sans payload ─────────────────────────────────────────
- (void)sendPacketType:(DPPacketType)type toSocket:(int)sock {
    DPHeader header;
    header.magic  = htonl(DP_MAGIC);
    header.type   = htonl((uint32_t)type);
    header.length = htonl(0);

    ssize_t sent = send(sock, &header, sizeof(DPHeader), 0);
    if (sent != sizeof(DPHeader)) {
        NSLog(@"[TCPReceiver] Erreur envoi paquet type=%u : %s", type, strerror(errno));
    }
}

// ─── Boucle de lecture des paquets ───────────────────────────────────────────
- (void)receiveLoopOnSocket:(int)sock {
    NSLog(@"[TCPReceiver] Boucle de réception démarrée (fd=%d)", sock);

    while (!self.shouldStop) {
        // 1. Lire l'en-tête
        DPHeader header;
        if (![self readExactly:sizeof(DPHeader) intoBuffer:(uint8_t *)&header fromSocket:sock]) {
            break;
        }

        // 2. Vérifier le magic
        uint32_t magic = ntohl(header.magic);
        if (magic != DP_MAGIC) {
            NSLog(@"[TCPReceiver] Magic invalide : 0x%08X (attendu 0x%08X)", magic, DP_MAGIC);
            break;
        }

        uint32_t type   = ntohl(header.type);
        uint32_t length = ntohl(header.length);

        // 3. Lire le payload si nécessaire
        NSData *payload = nil;
        if (length > 0) {
            // Allouer un buffer pour le payload (limite à 10 Mo par sécurité)
            if (length > 10 * 1024 * 1024) {
                NSLog(@"[TCPReceiver] Payload trop grand : %u bytes — déconnexion", length);
                break;
            }
            NSMutableData *data = [NSMutableData dataWithLength:length];
            if (![self readExactly:length intoBuffer:data.mutableBytes fromSocket:sock]) {
                break;
            }
            payload = [data copy];
        }

        // 4. Dispatcher selon le type
        switch ((DPPacketType)type) {

            case DPPacketTypeHELLO: {
                // Lire les infos Hello et répondre avec HELLO_ACK
                NSLog(@"[TCPReceiver] Paquet HELLO reçu");
                if (payload && payload.length >= sizeof(DPHelloPayload)) {
                    DPHelloPayload hello;
                    memcpy(&hello, payload.bytes, sizeof(DPHelloPayload));
                    // Sécuriser le nom (null-termination)
                    hello.device_name[63] = '\0';
                    NSLog(@"[TCPReceiver] Protocole v%d.%d — device : %s",
                          hello.version_major, hello.version_minor, hello.device_name);
                }
                [self sendPacketType:DPPacketTypeHELLO_ACK toSocket:sock];
                NSLog(@"[TCPReceiver] HELLO_ACK envoyé");
                break;
            }

            case DPPacketTypeCONFIG: {
                NSLog(@"[TCPReceiver] Paquet CONFIG reçu");
                if (payload && payload.length >= sizeof(DPConfigPayload)) {
                    DPConfigPayload config;
                    memcpy(&config, payload.bytes, sizeof(DPConfigPayload));
                    // Convertir big-endian → host
                    config.width       = ntohl(config.width);
                    config.height      = ntohl(config.height);
                    config.fps         = ntohl(config.fps);
                    config.bitrate     = ntohl(config.bitrate);
                    config.orientation = ntohl(config.orientation);

                    NSLog(@"[TCPReceiver] CONFIG : %dx%d@%ufps bitrate=%u orientation=%u",
                          config.width, config.height, config.fps, config.bitrate, config.orientation);

                    // Envoyer CONFIG_ACK
                    [self sendPacketType:DPPacketTypeCONFIG_ACK toSocket:sock];
                    NSLog(@"[TCPReceiver] CONFIG_ACK envoyé");

                    // Notifier le délégué sur le thread principal
                    id<TCPReceiverDelegate> delegate = self.delegate;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([delegate respondsToSelector:@selector(tcpReceiver:didReceiveConfig:)]) {
                            [delegate tcpReceiver:self didReceiveConfig:config];
                        }
                    });
                } else {
                    NSLog(@"[TCPReceiver] CONFIG trop court (%lu bytes)", (unsigned long)payload.length);
                }
                break;
            }

            case DPPacketTypeFRAME: {
                // Transmettre les NAL units brutes au délégué
                if (payload && payload.length > 0) {
                    id<TCPReceiverDelegate> delegate = self.delegate;
                    NSData *frameCopy = [payload copy];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([delegate respondsToSelector:@selector(tcpReceiver:didReceiveFrame:)]) {
                            [delegate tcpReceiver:self didReceiveFrame:frameCopy];
                        }
                    });
                }
                break;
            }

            case DPPacketTypePING: {
                // Répondre immédiatement avec PONG
                [self sendPacketType:DPPacketTypePONG toSocket:sock];
                break;
            }

            case DPPacketTypeDISCONNECT: {
                NSLog(@"[TCPReceiver] Paquet DISCONNECT reçu — fermeture propre");
                // Sortir de la boucle pour déclencher la déconnexion
                goto cleanup;
            }

            default:
                NSLog(@"[TCPReceiver] Type de paquet inconnu : %u — ignoré", type);
                break;
        }
    }

cleanup:
    NSLog(@"[TCPReceiver] Fin de la boucle de réception");
    close(sock);
    self.clientSocket = -1;

    // Notifier le délégué de la déconnexion sur le thread principal
    id<TCPReceiverDelegate> delegate = self.delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(tcpReceiverDidDisconnect:)]) {
            [delegate tcpReceiverDidDisconnect:self];
        }
    });

    // Si on n'a pas été arrêté volontairement, relancer l'écoute
    if (!self.shouldStop) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self acceptConnectionLoop];
        });
    }
}

// ─── Boucle d'attente de connexion ───────────────────────────────────────────
- (void)acceptConnectionLoop {
    NSLog(@"[TCPReceiver] En attente de connexion sur le port %d…", self.port);
    while (!self.shouldStop) {
        struct sockaddr_in clientAddr;
        socklen_t addrLen = sizeof(clientAddr);
        int clientSock = accept(self.serverSocket, (struct sockaddr *)&clientAddr, &addrLen);

        if (clientSock < 0) {
            if (self.shouldStop) break;
            if (errno == EINTR) continue;
            NSLog(@"[TCPReceiver] Erreur accept : %s", strerror(errno));
            break;
        }

        char clientIP[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &clientAddr.sin_addr, clientIP, sizeof(clientIP));
        NSLog(@"[TCPReceiver] Connexion acceptée depuis %s:%d", clientIP, ntohs(clientAddr.sin_port));

        self.clientSocket = clientSock;

        // Notifier le délégué de la connexion sur le thread principal
        id<TCPReceiverDelegate> delegate = self.delegate;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(tcpReceiverDidConnect:)]) {
                [delegate tcpReceiverDidConnect:self];
            }
        });

        // Démarrer la boucle de réception (bloquante, sur ce même thread)
        [self receiveLoopOnSocket:clientSock];

        // Après déconnexion, si shouldStop on sort, sinon on reboucle pour attendre
        if (self.shouldStop) break;
    }
}

// ─── API publique ─────────────────────────────────────────────────────────────

- (void)startListening {
    if (self.isListening) {
        NSLog(@"[TCPReceiver] Déjà en écoute");
        return;
    }

    self.shouldStop = NO;

    // Créer le socket serveur
    int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) {
        NSLog(@"[TCPReceiver] Impossible de créer le socket : %s", strerror(errno));
        return;
    }

    // Option SO_REUSEADDR pour éviter "Address already in use" après redémarrage
    int yes = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    // Bind sur toutes les interfaces, port configuré
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(self.port);

    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"[TCPReceiver] Erreur bind sur le port %d : %s", self.port, strerror(errno));
        close(sock);
        return;
    }

    if (listen(sock, 1) < 0) {
        NSLog(@"[TCPReceiver] Erreur listen : %s", strerror(errno));
        close(sock);
        return;
    }

    self.serverSocket = sock;
    self.isListening  = YES;
    NSLog(@"[TCPReceiver] Socket serveur prêt sur le port %d (fd=%d)", self.port, sock);

    // Lancer la boucle d'attente sur un thread en arrière-plan
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self acceptConnectionLoop];
    });
}

- (void)stopListening {
    if (!self.isListening) return;

    self.shouldStop  = YES;
    self.isListening = NO;

    // Fermer le socket serveur pour débloquer accept()
    if (self.serverSocket >= 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
    }

    // Fermer le socket client pour débloquer recv()
    if (self.clientSocket >= 0) {
        close(self.clientSocket);
        self.clientSocket = -1;
    }

    NSLog(@"[TCPReceiver] Arrêt de l'écoute");
}

@end
