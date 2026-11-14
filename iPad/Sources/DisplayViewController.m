// DisplayViewController.m — Affichage du flux H.264 via AVSampleBufferDisplayLayer
//
// Flux de données :
//   TCPReceiver → didReceiveFrame:(NSData*)nalData
//     → parsing SPS/PPS (NAL type 7/8)
//     → CMVideoFormatDescriptionCreateFromH264ParameterSets
//     → conversion start-codes → AVCC (préfixes de longueur 4 bytes)
//     → CMBlockBuffer + CMSampleBuffer
//     → [displayLayer enqueueSampleBuffer:]

#import "DisplayViewController.h"
#import <CoreMedia/CoreMedia.h>

// ─── Helpers NAL ─────────────────────────────────────────────────────────────

/// Cherche le prochain start code (0x00 0x00 0x00 0x01 ou 0x00 0x00 0x01) dans le buffer.
/// Retourne l'offset du premier 0x00 du start code, ou NSNotFound.
static NSUInteger findNextStartCode(const uint8_t *data, NSUInteger length, NSUInteger startOffset) {
    for (NSUInteger i = startOffset; i + 2 < length; i++) {
        if (data[i] == 0x00 && data[i+1] == 0x00) {
            if (i + 3 < length && data[i+2] == 0x01) {
                return i; // Start code 3 bytes
            }
            if (i + 3 < length && data[i+2] == 0x00 && data[i+3] == 0x01) {
                return i; // Start code 4 bytes
            }
        }
    }
    return NSNotFound;
}

/// Retourne la longueur du start code à l'offset donné (3 ou 4 bytes).
static NSUInteger startCodeLength(const uint8_t *data, NSUInteger length, NSUInteger offset) {
    if (offset + 3 < length && data[offset+2] == 0x00 && data[offset+3] == 0x01) {
        return 4;
    }
    return 3;
}

// ─── Interface privée ────────────────────────────────────────────────────────

@interface DisplayViewController ()
@property (nonatomic, strong) UILabel *overlayLabel;
@property (nonatomic, strong) NSData  *spsData;   // Derniers SPS reçus
@property (nonatomic, strong) NSData  *ppsData;   // Derniers PPS reçus
@property (nonatomic, strong) NSTimer *overlayTimer;
@property (nonatomic, assign) CMVideoFormatDescriptionRef cachedFormatDesc;
@property (nonatomic, assign) BOOL formatDescNeedsUpdate;
@end

// ─── Implémentation ──────────────────────────────────────────────────────────

@implementation DisplayViewController

// ── Cycle de vie de la vue ───────────────────────────────────────────────────

- (void)viewDidLoad {
    [super viewDidLoad];

    // Fond noir
    self.view.backgroundColor = [UIColor blackColor];

    // Configurer AVSampleBufferDisplayLayer — décodage H.264 matériel natif (A7)
    self.displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.displayLayer.opaque       = YES;
    self.displayLayer.backgroundColor = [UIColor blackColor].CGColor;
    self.displayLayer.frame = self.view.bounds;
    [self.view.layer addSublayer:self.displayLayer];

    // Overlay "En attente de connexion..." affiché dès le démarrage
    [self setupOverlayLabel];
    [self showOverlayWithText:@"En attente de connexion…" persistent:YES];

    // Créer et démarrer le récepteur TCP
    self.receiver          = [[TCPReceiver alloc] init];
    self.receiver.port     = 7000;
    self.receiver.delegate = self;
    [self.receiver startListening];

    NSLog(@"[DisplayVC] Vue chargée — récepteur TCP démarré sur le port 7000");
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Mettre à jour le frame du layer vidéo lors des rotations / redimensionnements
    self.displayLayer.frame = self.view.bounds;
}

// ── Orientation et UI ────────────────────────────────────────────────────────

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

// ── Overlay de statut ────────────────────────────────────────────────────────

- (void)setupOverlayLabel {
    self.overlayLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    self.overlayLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.overlayLabel.textAlignment    = NSTextAlignmentCenter;
    self.overlayLabel.textColor        = [UIColor whiteColor];
    self.overlayLabel.font             = [UIFont systemFontOfSize:24.0 weight:UIFontWeightMedium];
    self.overlayLabel.backgroundColor  = [UIColor colorWithWhite:0.0 alpha:0.6];
    self.overlayLabel.alpha            = 0.0;
    [self.view addSubview:self.overlayLabel];
}

/// Affiche un message dans l'overlay.
/// Si persistent=YES, l'overlay reste jusqu'au prochain appel.
/// Si persistent=NO, il disparaît après 2 secondes.
- (void)showOverlayWithText:(NSString *)text persistent:(BOOL)persistent {
    [self.overlayTimer invalidate];
    self.overlayLabel.text = text;

    [UIView animateWithDuration:0.3 animations:^{
        self.overlayLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (!persistent) {
            self.overlayTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                                 target:self
                                                               selector:@selector(hideOverlay)
                                                               userInfo:nil
                                                                repeats:NO];
        }
    }];
}

- (void)hideOverlay {
    [UIView animateWithDuration:0.5 animations:^{
        self.overlayLabel.alpha = 0.0;
    }];
}

// ── Helpers NAL units → CMSampleBuffer ──────────────────────────────────────

/// Extrait les NAL units individuelles depuis un buffer Annex B (start codes).
/// Retourne un tableau de NSData (payload de chaque NAL, sans start code).
- (NSArray<NSData *> *)parseNALUnitsFromData:(NSData *)data {
    NSMutableArray<NSData *> *nalUnits = [NSMutableArray array];
    const uint8_t *bytes = data.bytes;
    NSUInteger length    = data.length;
    NSUInteger i         = 0;

    while (i < length) {
        // Trouver le prochain start code
        NSUInteger scOffset = findNextStartCode(bytes, length, i);
        if (scOffset == NSNotFound) break;

        NSUInteger scLen  = startCodeLength(bytes, length, scOffset);
        NSUInteger nalStart = scOffset + scLen;

        // Trouver le start code suivant pour connaître la fin de ce NAL
        NSUInteger nextSC = findNextStartCode(bytes, length, nalStart);
        NSUInteger nalEnd = (nextSC == NSNotFound) ? length : nextSC;

        if (nalEnd > nalStart) {
            [nalUnits addObject:[NSData dataWithBytes:bytes + nalStart
                                               length:nalEnd - nalStart]];
        }
        i = nalEnd;
    }
    return nalUnits;
}

/// Crée ou met à jour le CMVideoFormatDescription H.264 (avc1) depuis des NAL SPS+PPS.
- (CMVideoFormatDescriptionRef)createFormatDescriptionFromSPS:(NSData *)sps pps:(NSData *)pps {
    const uint8_t *spsBytes = sps.bytes;
    const uint8_t *ppsBytes = pps.bytes;
    const uint8_t *paramSets[2] = { spsBytes, ppsBytes };
    size_t  paramSizes[2]       = { sps.length, pps.length };

    CMVideoFormatDescriptionRef formatDesc = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
        kCFAllocatorDefault,
        2,            // Nombre de parameter sets (SPS + PPS)
        paramSets,
        paramSizes,
        4,            // Longueur du préfixe AVCC en bytes
        &formatDesc
    );

    if (status != noErr) {
        NSLog(@"[DisplayVC] Erreur CMVideoFormatDescriptionCreateFromH264ParameterSets : %d", (int)status);
        return NULL;
    }
    return formatDesc;
}

/// Convertit un buffer de NAL units Annex B en AVCC (préfixes de longueur 4 bytes).
/// Retourne les données converties prêtes pour CMBlockBuffer.
- (NSData *)convertAnnexBToAVCC:(NSData *)annexBData {
    NSArray<NSData *> *nalUnits = [self parseNALUnitsFromData:annexBData];
    NSMutableData *avccData = [NSMutableData data];

    for (NSData *nal in nalUnits) {
        uint8_t nalType = ((uint8_t *)nal.bytes)[0] & 0x1F;
        // Ignorer SPS (7) et PPS (8) dans les frames — ils sont gérés séparément
        if (nalType == 7 || nalType == 8) continue;

        // Préfixe de longueur 4 bytes big-endian (format AVCC)
        uint32_t nalLength = htonl((uint32_t)nal.length);
        [avccData appendBytes:&nalLength length:4];
        [avccData appendData:nal];
    }
    return avccData;
}

/// Crée un CMSampleBuffer H.264 depuis des données AVCC et un CMVideoFormatDescription.
- (CMSampleBufferRef)createSampleBufferFromAVCCData:(NSData *)avccData
                                      formatDesc:(CMVideoFormatDescriptionRef)formatDesc {
    if (!avccData || avccData.length == 0 || !formatDesc) return NULL;

    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault,
        NULL,                    // Alloue un nouveau bloc mémoire indépendant
        avccData.length,
        kCFAllocatorDefault,
        NULL,
        0,
        avccData.length,
        0,
        &blockBuffer
    );

    if (status != kCMBlockBufferNoErr || !blockBuffer) {
        NSLog(@"[DisplayVC] Erreur CMBlockBufferCreateWithMemoryBlock : %d", (int)status);
        return NULL;
    }

    status = CMBlockBufferReplaceDataBytes(avccData.bytes, blockBuffer, 0, avccData.length);
    if (status != kCMBlockBufferNoErr) {
        NSLog(@"[DisplayVC] Erreur CMBlockBufferReplaceDataBytes : %d", (int)status);
        CFRelease(blockBuffer);
        return NULL;
    }

    // Paramètres temporels — temps invalide pour lecture immédiate (live)
    CMSampleTimingInfo timingInfo = {
        .duration               = kCMTimeInvalid,
        .presentationTimeStamp  = kCMTimeInvalid,
        .decodeTimeStamp        = kCMTimeInvalid
    };

    CMSampleBufferRef sampleBuffer = NULL;
    size_t sampleSize = avccData.length;
    status = CMSampleBufferCreateReady(
        kCFAllocatorDefault,
        blockBuffer,
        formatDesc,
        1,
        1,
        &timingInfo,
        1,
        &sampleSize,
        &sampleBuffer
    );

    CFRelease(blockBuffer);

    if (status != noErr || !sampleBuffer) {
        NSLog(@"[DisplayVC] Erreur CMSampleBufferCreateReady : %d", (int)status);
        return NULL;
    }

    // CRUCIAL pour AVSampleBufferDisplayLayer sans timebase : affichage immédiat
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    }

    return sampleBuffer;
}

// ── TCPReceiverDelegate ──────────────────────────────────────────────────────

- (void)tcpReceiverDidConnect:(TCPReceiver *)receiver {
    NSLog(@"[DisplayVC] Mac connecté — démarrage de l'affichage H.264");
    [self showOverlayWithText:@"Connecté" persistent:NO];
}

- (void)tcpReceiverDidDisconnect:(TCPReceiver *)receiver {
    NSLog(@"[DisplayVC] Connexion perdue — en attente…");
    [self showOverlayWithText:@"En attente de connexion…" persistent:YES];

    // Vider le layer vidéo
    [self.displayLayer flushAndRemoveImage];
}

- (void)tcpReceiver:(TCPReceiver *)receiver didReceiveConfig:(DPConfigPayload)config {
    NSLog(@"[DisplayVC] CONFIG reçu : %dx%d@%ufps orientation=%u",
          config.width, config.height, config.fps, config.orientation);

    // Mettre à jour l'orientation de l'interface si nécessaire
    // (iOS 12 : forcer la rotation via le AppDelegate si besoin)
    // Pour l'instant on accepte toutes les orientations
}

- (void)tcpReceiver:(TCPReceiver *)receiver didReceiveFrame:(NSData *)nalData {
    if (nalData.length == 0) return;

    // ── Étape 1 : Parser les NAL units pour détecter SPS/PPS ───────────────
    NSArray<NSData *> *nalUnits = [self parseNALUnitsFromData:nalData];

    for (NSData *nal in nalUnits) {
        if (nal.length == 0) continue;
        uint8_t nalType = ((uint8_t *)nal.bytes)[0] & 0x1F;
        if (nalType == 7) { // SPS
            self.spsData = nal;
            self.formatDescNeedsUpdate = YES;
            NSLog(@"[DisplayVC] SPS reçu (%lu bytes)", (unsigned long)nal.length);
        } else if (nalType == 8) { // PPS
            self.ppsData = nal;
            self.formatDescNeedsUpdate = YES;
            NSLog(@"[DisplayVC] PPS reçu (%lu bytes)", (unsigned long)nal.length);
        }
    }

    // ── Étape 2 : Vérifier qu'on a SPS+PPS avant de décoder ────────────────
    if (!self.spsData || !self.ppsData) {
        NSLog(@"[DisplayVC] En attente de SPS/PPS — frame ignorée");
        return;
    }

    // ── Étape 3 : Créer/récupérer le CMVideoFormatDescription mis en cache ─
    if (!self.cachedFormatDesc || self.formatDescNeedsUpdate) {
        if (self.cachedFormatDesc) {
            CFRelease(self.cachedFormatDesc);
            self.cachedFormatDesc = NULL;
        }
        self.cachedFormatDesc = [self createFormatDescriptionFromSPS:self.spsData pps:self.ppsData];
        self.formatDescNeedsUpdate = NO;
        NSLog(@"[DisplayVC] Nouveau CMVideoFormatDescription créé");
    }

    if (!self.cachedFormatDesc) {
        NSLog(@"[DisplayVC] Format description absent — frame ignorée");
        return;
    }

    // ── Étape 4 : Convertir Annex B → AVCC ─────────────────────────────────
    NSData *avccData = [self convertAnnexBToAVCC:nalData];
    if (avccData.length == 0) {
        return; // Frame SPS/PPS pure sans données VCL
    }

    // ── Étape 5 : Créer le CMSampleBuffer ───────────────────────────────────
    CMSampleBufferRef sampleBuffer = [self createSampleBufferFromAVCCData:avccData
                                                               formatDesc:self.cachedFormatDesc];
    if (!sampleBuffer) {
        NSLog(@"[DisplayVC] Impossible de créer le CMSampleBuffer");
        return;
    }

    // ── Masquer l'overlay à la première image valide ───────────────────────
    if (self.overlayLabel.alpha > 0.0) {
        [self hideOverlay];
    }

    // ── Étape 6 : Enqueuer sur AVSampleBufferDisplayLayer ───────────────────
    if (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        NSError *err = self.displayLayer.error;
        NSLog(@"[DisplayVC] Layer en erreur : %@ — flush", err.localizedDescription);
        [self.displayLayer flushAndRemoveImage];
    }

    [self.displayLayer enqueueSampleBuffer:sampleBuffer];

    // Ne JAMAIS appeler CMSampleBufferInvalidate ici : enqueueSampleBuffer est asynchrone !
    CFRelease(sampleBuffer);
}

// ── Nettoyage ────────────────────────────────────────────────────────────────

- (void)dealloc {
    [self.receiver stopListening];
    if (self.cachedFormatDesc) {
        CFRelease(self.cachedFormatDesc);
        self.cachedFormatDesc = NULL;
    }
    if (self.decompressionSession) {
        VTDecompressionSessionInvalidate(self.decompressionSession);
        CFRelease(self.decompressionSession);
        self.decompressionSession = NULL;
    }
}

@end
