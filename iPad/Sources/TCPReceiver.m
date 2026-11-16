// TCPReceiver.m — Implémentation de la réception TCP DisplayPAD

#import "TCPReceiver.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>

@interface TCPReceiver () <NSNetServiceDelegate>
@property (nonatomic, assign) int serverSocket;   // Socket d'écoute serveur TCP
@property (nonatomic, assign) int clientSocket;   // Socket client TCP connecté
@property (nonatomic, assign) int udpSocket;      // Socket d'écoute UDP vidéo (port 7001)
@property (nonatomic, strong) NSNetService *netService; // Annonce Bonjour / AWDL Peer-to-Peer
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
        _udpSocket     = -1;
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
        struct sockaddr_storage clientAddr;
        socklen_t addrLen = sizeof(clientAddr);
        int clientSock = accept(self.serverSocket, (struct sockaddr *)&clientAddr, &addrLen);

        if (clientSock < 0) {
            if (self.shouldStop) break;
            if (errno == EINTR) continue;
            NSLog(@"[TCPReceiver] Erreur accept : %s", strerror(errno));
            break;
        }

        char clientIP[INET6_ADDRSTRLEN] = {0};
        if (clientAddr.ss_family == AF_INET) {
            struct sockaddr_in *s = (struct sockaddr_in *)&clientAddr;
            inet_ntop(AF_INET, &s->sin_addr, clientIP, sizeof(clientIP));
        } else if (clientAddr.ss_family == AF_INET6) {
            struct sockaddr_in6 *s = (struct sockaddr_in6 *)&clientAddr;
            inet_ntop(AF_INET6, &s->sin6_addr, clientIP, sizeof(clientIP));
        }
        NSLog(@"[TCPReceiver] Connexion acceptée depuis %s", clientIP);

        int nodelay = 1;
        setsockopt(clientSock, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));

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

// ─── Boucle de réception UDP vidéo (port 7001) ────────────────────────────────
- (void)udpReceiveLoop {
    NSLog(@"[UDPReceiver] Boucle de réception UDP démarrée sur le port %d", DP_UDP_PORT);

    uint8_t buf[2048];
    uint32_t currentFrameId = 0;
    uint16_t expectedChunks = 0;
    BOOL hasActiveFrame = NO;
    NSMutableDictionary<NSNumber *, NSData *> *chunks = [NSMutableDictionary dictionary];

    while (!self.shouldStop && self.udpSocket >= 0) {
        ssize_t n = recvfrom(self.udpSocket, buf, sizeof(buf), 0, NULL, NULL);
        if (n < 0) {
            if (self.shouldStop) break;
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
            NSLog(@"[UDPReceiver] Erreur recvfrom : %s", strerror(errno));
            break;
        }
        if ((size_t)n < sizeof(DPUDPChunkHeader)) continue;

        DPUDPChunkHeader hdr;
        memcpy(&hdr, buf, sizeof(DPUDPChunkHeader));
        if (ntohl(hdr.magic) != DP_UDP_MAGIC) continue;

        uint32_t frameId    = ntohl(hdr.frame_id);
        uint16_t chunkIndex = ntohs(hdr.chunk_index);
        uint16_t chunkCount = ntohs(hdr.chunk_count);

        if (chunkCount == 0 || chunkIndex >= chunkCount) continue;

        if (!hasActiveFrame || frameId != currentFrameId) {
            // Ignorer les paquets obsolètes d'une image déjà dépassée
            if (hasActiveFrame && frameId < currentFrameId && (currentFrameId - frameId) < 1000) {
                continue;
            }
            [chunks removeAllObjects];
            currentFrameId = frameId;
            expectedChunks = chunkCount;
            hasActiveFrame = YES;
        }

        size_t payloadLen = (size_t)n - sizeof(DPUDPChunkHeader);
        NSData *chunkData = [NSData dataWithBytes:(buf + sizeof(DPUDPChunkHeader)) length:payloadLen];
        chunks[@(chunkIndex)] = chunkData;

        if (chunks.count == expectedChunks) {
            NSMutableData *fullFrame = [NSMutableData dataWithCapacity:expectedChunks * DP_UDP_MAX_CHUNK];
            BOOL complete = YES;
            for (uint16_t i = 0; i < expectedChunks; i++) {
                NSData *part = chunks[@(i)];
                if (!part) { complete = NO; break; }
                [fullFrame appendData:part];
            }
            [chunks removeAllObjects];
            hasActiveFrame = NO;

            if (complete && fullFrame.length > 0) {
                NSData *immutableFrame = [fullFrame copy];
                id<TCPReceiverDelegate> delegate = self.delegate;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([delegate respondsToSelector:@selector(tcpReceiver:didReceiveFrame:)]) {
                        [delegate tcpReceiver:self didReceiveFrame:immutableFrame];
                    }
                });
            }
        }
    }
    NSLog(@"[UDPReceiver] Boucle de réception UDP terminée");
}

// ─── API publique ─────────────────────────────────────────────────────────────

- (void)startListening {
    if (self.isListening) {
        NSLog(@"[TCPReceiver] Déjà en écoute");
        return;
    }

    self.shouldStop = NO;

    // 1. Créer le socket serveur TCP dual-stack IPv4+IPv6 (supporte USB, Wi-Fi IPv4, et AWDL IPv6)
    int sock = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) {
        NSLog(@"[TCPReceiver] Impossible de créer le socket : %s", strerror(errno));
        return;
    }

    int yes = 1;
    int no  = 0;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(sock, IPPROTO_IPV6, IPV6_V6ONLY, &no, sizeof(no)); // Accepte IPv4 et IPv6

    struct sockaddr_in6 addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin6_family = AF_INET6;
    addr.sin6_addr   = in6addr_any;
    addr.sin6_port   = htons(self.port);

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

    // 2. Créer le socket UDP vidéo dual-stack IPv4+IPv6 (port 7001, ultra-basse latence Wi-Fi/AWDL)
    int udpSock = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP);
    if (udpSock >= 0) {
        setsockopt(udpSock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        setsockopt(udpSock, IPPROTO_IPV6, IPV6_V6ONLY, &no, sizeof(no));
        int rcvBuf = 512 * 1024;
        setsockopt(udpSock, SOL_SOCKET, SO_RCVBUF, &rcvBuf, sizeof(rcvBuf));

        struct sockaddr_in6 udpAddr;
        memset(&udpAddr, 0, sizeof(udpAddr));
        udpAddr.sin6_family = AF_INET6;
        udpAddr.sin6_addr   = in6addr_any;
        udpAddr.sin6_port   = htons(DP_UDP_PORT);

        if (bind(udpSock, (struct sockaddr *)&udpAddr, sizeof(udpAddr)) == 0) {
            self.udpSocket = udpSock;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [self udpReceiveLoop];
            });
        } else {
            NSLog(@"[UDPReceiver] Erreur bind UDP port %d : %s", DP_UDP_PORT, strerror(errno));
            close(udpSock);
        }
    }

    self.isListening  = YES;
    NSLog(@"[TCPReceiver] Serveur dual-stack prêt : TCP:%d + UDP:%d", self.port, DP_UDP_PORT);

    // 3. Publier le service Bonjour avec support Peer-to-Peer (AWDL Wi-Fi Direct)
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.netService stop];
        self.netService = [[NSNetService alloc] initWithDomain:@"local."
                                                          type:@"_displaypad._tcp."
                                                          name:@""
                                                          port:self.port];
        self.netService.includesPeerToPeer = YES;
        self.netService.delegate = self;
        [self.netService publish];
        NSLog(@"[Bonjour] Service _displaypad._tcp publié (AWDL Peer-to-Peer activé)");
    });

    // Lancer la boucle d'attente TCP sur un thread en arrière-plan
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self acceptConnectionLoop];
    });
}

- (void)stopListening {
    if (!self.isListening) return;

    self.shouldStop  = YES;
    self.isListening = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.netService stop];
        self.netService = nil;
    });

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

    // Fermer le socket UDP pour débloquer recvfrom()
    if (self.udpSocket >= 0) {
        close(self.udpSocket);
        self.udpSocket = -1;
    }

    NSLog(@"[TCPReceiver] Arrêt de l'écoute");
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidPublish:(NSNetService *)sender {
    NSLog(@"[Bonjour] Service publié avec succès : %@", sender.name);
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"[Bonjour] Échec publication service : %@", errorDict);
}

@end
