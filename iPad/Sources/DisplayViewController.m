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
@property (nonatomic, strong) UIView   *videoContainerView; // Conteneur zoomable/déplaçable
@property (nonatomic, strong) UILabel  *overlayLabel;
@property (nonatomic, strong) NSData   *spsData;   // Derniers SPS reçus
@property (nonatomic, strong) NSData   *ppsData;   // Derniers PPS reçus
@property (nonatomic, strong) NSTimer  *overlayTimer;
@property (nonatomic, assign) CMVideoFormatDescriptionRef cachedFormatDesc;
@property (nonatomic, assign) BOOL     formatDescNeedsUpdate;

// Zoom & Pan
@property (nonatomic, assign) CGFloat  currentZoomScale;
@property (nonatomic, assign) CGPoint  currentPanOffset;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer   *panRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer   *doubleTapRecognizer;

// Menu Réglages (geste 3 doigts)
@property (nonatomic, strong) UITapGestureRecognizer   *threeFingerTapRecognizer;
@property (nonatomic, strong) SettingsOverlayView      *settingsOverlay;

// Télémétrie & État
@property (nonatomic, copy)   NSString *connectedClientIP;
@property (nonatomic, assign) CGSize   streamResolution;
@property (nonatomic, assign) NSUInteger frameCountInWindow;
@property (nonatomic, strong) NSDate   *lastFPSCalculationDate;
@property (nonatomic, assign) NSUInteger currentCalculatedFPS;
@end

// ─── Implémentation ──────────────────────────────────────────────────────────

@implementation DisplayViewController

// ── Cycle de vie de la vue ───────────────────────────────────────────────────

- (void)viewDidLoad {
    [super viewDidLoad];

    // Valeurs initiales zoom
    _currentZoomScale = 1.0;
    _currentPanOffset = CGPointZero;
    _lastFPSCalculationDate = [NSDate date];

    // Fond noir
    self.view.backgroundColor = [UIColor blackColor];

    // Conteneur vidéo zoomable
    self.videoContainerView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.videoContainerView.backgroundColor = [UIColor blackColor];
    self.videoContainerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.videoContainerView];

    // Configurer AVSampleBufferDisplayLayer — décodage H.264 matériel natif (A7)
    self.displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.displayLayer.opaque       = YES;
    self.displayLayer.backgroundColor = [UIColor blackColor].CGColor;
    self.displayLayer.frame = self.videoContainerView.bounds;
    [self.videoContainerView.layer addSublayer:self.displayLayer];

    // Configurer les gestes interactifs
    [self setupGestures];

    // Overlay "En attente de connexion..." affiché dès le démarrage
    [self setupOverlayLabel];
    [self showOverlayWithText:@"En attente de connexion…" persistent:YES];

    // Créer et démarrer le récepteur TCP
    self.receiver          = [[TCPReceiver alloc] init];
    self.receiver.port     = 7000;
    self.receiver.delegate = self;
    [self.receiver startListening];

    NSLog(@"[DisplayVC] Vue chargée — récepteur TCP démarré sur le port 7000 (gestes zoom & 3 doigts actifs)");
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Ajuster le conteneur et le layer vidéo uniquement si on n'est pas zoomé
    if (self.currentZoomScale <= 1.01) {
        self.videoContainerView.transform = CGAffineTransformIdentity;
        self.videoContainerView.frame = self.view.bounds;
        self.displayLayer.frame = self.videoContainerView.bounds;
    }
}

// ── Configuration des Gestes (Zoom, Pan, 3 Doigts) ───────────────────────────

- (void)setupGestures {
    // 1. Geste 3 doigts n'importe où sur l'écran : ouvre le menu Réglages
    self.threeFingerTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleThreeFingerTap:)];
    self.threeFingerTapRecognizer.numberOfTouchesRequired = 3;
    self.threeFingerTapRecognizer.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.threeFingerTapRecognizer];

    // 2. Pinch à 2 doigts : zoomer / dézoomer
    self.pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    self.pinchRecognizer.delegate = self;
    self.pinchRecognizer.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.pinchRecognizer];

    // 3. Pan à 2 doigts : déplacer l'affichage lorsque l'on est zoomé
    self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.panRecognizer.minimumNumberOfTouches = 2;
    self.panRecognizer.maximumNumberOfTouches = 2;
    self.panRecognizer.delegate = self;
    self.panRecognizer.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.panRecognizer];

    // 4. Double-tap à 2 doigts : réinitialiser instantanément le zoom à 1:1
    self.doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    self.doubleTapRecognizer.numberOfTapsRequired = 2;
    self.doubleTapRecognizer.numberOfTouchesRequired = 2;
    self.doubleTapRecognizer.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.doubleTapRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // Autoriser pinch et pan à 2 doigts simultanément
    if ((gestureRecognizer == self.pinchRecognizer && otherGestureRecognizer == self.panRecognizer) ||
        (gestureRecognizer == self.panRecognizer && otherGestureRecognizer == self.pinchRecognizer)) {
        return YES;
    }
    return NO;
}

// ── Gestionnaires d'actions gestuelles ────────────────────────────────────────

- (void)handleThreeFingerTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self toggleSettingsOverlay];
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat newScale = self.currentZoomScale * gesture.scale;
        // Limiter le facteur d'échelle entre 1.0x et 5.0x
        newScale = MAX(1.0, MIN(newScale, 5.0));

        [self applyZoomScale:newScale panOffset:self.currentPanOffset];
        gesture.scale = 1.0;
        self.currentZoomScale = newScale;

        if (self.settingsOverlay.superview) {
            [self.settingsOverlay updateZoomScale:self.currentZoomScale];
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        if (self.currentZoomScale <= 1.01) {
            [self resetZoomAnimated:YES];
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (self.currentZoomScale <= 1.01) return; // Pas de pan à l'échelle 1:1

    CGPoint translation = [gesture translationInView:self.view];

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint newOffset = CGPointMake(self.currentPanOffset.x + translation.x,
                                        self.currentPanOffset.y + translation.y);

        // Clamping des bords pour éviter de faire sortir l'image de l'écran
        CGFloat maxOffsetX = (self.view.bounds.size.width * (self.currentZoomScale - 1.0)) / 2.0;
        CGFloat maxOffsetY = (self.view.bounds.size.height * (self.currentZoomScale - 1.0)) / 2.0;

        newOffset.x = MAX(-maxOffsetX, MIN(newOffset.x, maxOffsetX));
        newOffset.y = MAX(-maxOffsetY, MIN(newOffset.y, maxOffsetY));

        [self applyZoomScale:self.currentZoomScale panOffset:newOffset];
        [gesture setTranslation:CGPointZero inView:self.view];
        self.currentPanOffset = newOffset;
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self resetZoomAnimated:YES];
    }
}

- (void)applyZoomScale:(CGFloat)scale panOffset:(CGPoint)offset {
    if (scale <= 1.001) {
        self.videoContainerView.transform = CGAffineTransformIdentity;
        return;
    }
    // Translation appliquée par rapport au centre redimensionné
    CGAffineTransform transform = CGAffineTransformMakeTranslation(offset.x, offset.y);
    transform = CGAffineTransformScale(transform, scale, scale);
    self.videoContainerView.transform = transform;
}

- (void)resetZoomAnimated:(BOOL)animated {
    void (^resetBlock)(void) = ^{
        self.videoContainerView.transform = CGAffineTransformIdentity;
    };

    self.currentZoomScale = 1.0;
    self.currentPanOffset = CGPointZero;

    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:resetBlock completion:nil];
    } else {
        resetBlock();
    }

    if (self.settingsOverlay.superview) {
        [self.settingsOverlay updateZoomScale:1.0];
    }
}

// ── Gestion du Menu Réglages (Overlay 3 Doigts) ──────────────────────────────

- (void)toggleSettingsOverlay {
    if (self.settingsOverlay && self.settingsOverlay.superview) {
        [self.settingsOverlay dismiss];
    } else {
        if (!self.settingsOverlay) {
            self.settingsOverlay = [[SettingsOverlayView alloc] initWithFrame:self.view.bounds];
            self.settingsOverlay.delegate = self;
        }
        [self.settingsOverlay setVideoGravity:self.displayLayer.videoGravity];
        [self.settingsOverlay updateZoomScale:self.currentZoomScale];
        [self.settingsOverlay updateFPS:self.currentCalculatedFPS];
        if (!CGSizeEqualToSize(self.streamResolution, CGSizeZero)) {
            [self.settingsOverlay updateResolution:self.streamResolution];
        }
        BOOL isConnected = (self.receiver != nil && self.connectedClientIP != nil);
        [self.settingsOverlay updateConnectionState:isConnected ? @"Connecté" : @"En attente…"
                                        isConnected:isConnected
                                           clientIP:self.connectedClientIP];
        [self.settingsOverlay showInView:self.view];
    }
}

// ── SettingsOverlayDelegate ──────────────────────────────────────────────────

- (void)settingsOverlayDidRequestResetZoom:(SettingsOverlayView *)overlay {
    [self resetZoomAnimated:YES];
}

- (void)settingsOverlay:(SettingsOverlayView *)overlay didChangeVideoGravity:(AVLayerVideoGravity)gravity {
    self.displayLayer.videoGravity = gravity;
}

- (void)settingsOverlayDidRequestReconnect:(SettingsOverlayView *)overlay {
    NSLog(@"[DisplayVC] Demande de reconnexion depuis le menu Réglages");
    [self.displayLayer flushAndRemoveImage];
    [self.receiver stopListening];
    [self.receiver startListening];
    [self showOverlayWithText:@"Réinitialisation du récepteur…" persistent:NO];
    [overlay dismiss];
}

- (void)settingsOverlayDidDismiss:(SettingsOverlayView *)overlay {
    NSLog(@"[DisplayVC] Menu Réglages fermé");
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
    self.connectedClientIP = @"Mac";
    if (self.settingsOverlay.superview) {
        [self.settingsOverlay updateConnectionState:@"Connecté" isConnected:YES clientIP:self.connectedClientIP];
    }
    [self showOverlayWithText:@"Connecté" persistent:NO];
}

- (void)tcpReceiverDidDisconnect:(TCPReceiver *)receiver {
    NSLog(@"[DisplayVC] Connexion perdue — en attente…");
    self.connectedClientIP = nil;
    self.currentCalculatedFPS = 0;
    self.frameCountInWindow = 0;
    if (self.settingsOverlay.superview) {
        [self.settingsOverlay updateConnectionState:@"En attente…" isConnected:NO clientIP:nil];
        [self.settingsOverlay updateFPS:0];
    }
    [self showOverlayWithText:@"En attente de connexion…" persistent:YES];

    // Vider le layer vidéo
    [self.displayLayer flushAndRemoveImage];
}

- (void)tcpReceiver:(TCPReceiver *)receiver didReceiveConfig:(DPConfigPayload)config {
    NSLog(@"[DisplayVC] CONFIG reçu : %dx%d@%ufps orientation=%u",
          config.width, config.height, config.fps, config.orientation);

    self.streamResolution = CGSizeMake(config.width, config.height);
    if (self.settingsOverlay.superview) {
        [self.settingsOverlay updateResolution:self.streamResolution];
    }
}

- (void)tcpReceiver:(TCPReceiver *)receiver didReceiveFrame:(NSData *)nalData {
    if (nalData.length == 0) return;

    // Calcul FPS
    self.frameCountInWindow++;
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.lastFPSCalculationDate];
    if (elapsed >= 1.0) {
        self.currentCalculatedFPS = (NSUInteger)round(self.frameCountInWindow / elapsed);
        self.frameCountInWindow = 0;
        self.lastFPSCalculationDate = [NSDate date];
        if (self.settingsOverlay.superview) {
            [self.settingsOverlay updateFPS:self.currentCalculatedFPS];
        }
    }

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
