// SettingsOverlayView.m — Implémentation du menu réglages iPad
//
// Conçu pour iOS 12+ (iPad Air 1) et versions supérieures.

#import "SettingsOverlayView.h"
#import <ifaddrs.h>
#import <arpa/inet.h>

@interface SettingsOverlayView ()
@property (nonatomic, strong) UIView *dimmedBackground;
@property (nonatomic, strong) UIVisualEffectView *cardView;
@property (nonatomic, strong) UILabel *ipValueLabel;
@property (nonatomic, strong) UILabel *statusValueLabel;
@property (nonatomic, strong) UILabel *zoomValueLabel;
@property (nonatomic, strong) UILabel *statsValueLabel;
@property (nonatomic, strong) UISegmentedControl *gravitySegment;
@property (nonatomic, strong) UIButton *resetZoomButton;
@property (nonatomic, assign) CGFloat currentZoom;
@end

@implementation SettingsOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _currentZoom = 1.0;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self setupUI];
    }
    return self;
}

// ─── Récupération de l'IP Wi-Fi (en0) ─────────────────────────────────────────

+ (NSString *)localWiFiIPAddress {
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;

    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr != NULL && temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"]) {
                    struct sockaddr_in *sockaddr = (struct sockaddr_in *)temp_addr->ifa_addr;
                    address = [NSString stringWithUTF8String:inet_ntoa(sockaddr->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address ?: @"Non connecté au Wi-Fi";
}

// ─── Construction de l'interface ─────────────────────────────────────────────

- (void)setupUI {
    // 1. Fond sombre atténué
    self.dimmedBackground = [[UIView alloc] initWithFrame:self.bounds];
    self.dimmedBackground.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    self.dimmedBackground.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.dimmedBackground];

    UITapGestureRecognizer *tapBg = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    [self.dimmedBackground addGestureRecognizer:tapBg];

    // 2. Carte modale centrale en verre dépoli
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.cardView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.cardView.layer.cornerRadius = 16.0;
    self.cardView.layer.masksToBounds = YES;
    self.cardView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.cardView.layer.borderWidth = 1.0;
    [self addSubview:self.cardView];

    UIView *content = self.cardView.contentView;

    // 3. En-tête : Titre & Bouton Fermer
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"DisplayPAD — Réglages";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:titleLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:closeBtn];

    // Séparateur 1
    UIView *sep1 = [self createSeparator];
    [content addSubview:sep1];

    // 4. Section SANS-FIL (Wi-Fi)
    UILabel *wifiHeader = [self createSectionHeader:@"SANS-FIL (WI-FI)"];
    [content addSubview:wifiHeader];

    UILabel *wifiExplain = [[UILabel alloc] init];
    wifiExplain.text = @"Pour vous connecter sans câble, entrez cette IP sur votre Mac :";
    wifiExplain.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    wifiExplain.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    wifiExplain.numberOfLines = 0;
    wifiExplain.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:wifiExplain];

    self.ipValueLabel = [[UILabel alloc] init];
    NSString *ip = [SettingsOverlayView localWiFiIPAddress];
    self.ipValueLabel.text = [NSString stringWithFormat:@"%@:7000", ip];
    self.ipValueLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0]; // Bleu cyan
    self.ipValueLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:17] ?: [UIFont boldSystemFontOfSize:17];
    self.ipValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.ipValueLabel];

    self.statusValueLabel = [[UILabel alloc] init];
    self.statusValueLabel.text = @"Statut : En attente de connexion…";
    self.statusValueLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    self.statusValueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.statusValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.statusValueLabel];

    // Séparateur 2
    UIView *sep2 = [self createSeparator];
    [content addSubview:sep2];

    // 5. Section ZOOM & ÉCRAN
    UILabel *zoomHeader = [self createSectionHeader:@"ZOOM & AFFICHAGE"];
    [content addSubview:zoomHeader];

    self.zoomValueLabel = [[UILabel alloc] init];
    self.zoomValueLabel.text = @"Zoom : 1.0x (100%)";
    self.zoomValueLabel.textColor = [UIColor whiteColor];
    self.zoomValueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.zoomValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.zoomValueLabel];

    self.resetZoomButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetZoomButton setTitle:@"Réinitialiser Zoom (1:1)" forState:UIControlStateNormal];
    [self.resetZoomButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.resetZoomButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.8];
    self.resetZoomButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.resetZoomButton.layer.cornerRadius = 8.0;
    self.resetZoomButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resetZoomButton addTarget:self action:@selector(handleResetZoom) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:self.resetZoomButton];

    NSArray *gravityItems = @[@"Adapter (Fit)", @"Remplir (Fill)"];
    self.gravitySegment = [[UISegmentedControl alloc] initWithItems:gravityItems];
    self.gravitySegment.selectedSegmentIndex = 0;
    self.gravitySegment.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
    self.gravitySegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gravitySegment addTarget:self action:@selector(handleGravityChange:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:self.gravitySegment];

    UILabel *gesturesTip = [[UILabel alloc] init];
    gesturesTip.text = @"• Pincez à 2 doigts pour zoomer / dézoomer\n• Glissez à 2 doigts pour naviguer\n• Double-tap à 2 doigts pour réinitialiser";
    gesturesTip.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    gesturesTip.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    gesturesTip.numberOfLines = 3;
    gesturesTip.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:gesturesTip];

    // Séparateur 3
    UIView *sep3 = [self createSeparator];
    [content addSubview:sep3];

    // 6. Section TÉLÉMÉTRIE & ACTIONS
    UILabel *statsHeader = [self createSectionHeader:@"FLUX VIDÉO"];
    [content addSubview:statsHeader];

    self.statsValueLabel = [[UILabel alloc] init];
    self.statsValueLabel.text = @"FPS : -- | Résolution : --";
    self.statsValueLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.statsValueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.statsValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.statsValueLabel];

    UIButton *reconnectBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [reconnectBtn setTitle:@"Réinitialiser la connexion" forState:UIControlStateNormal];
    [reconnectBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0] forState:UIControlStateNormal];
    reconnectBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    reconnectBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    reconnectBtn.layer.cornerRadius = 8.0;
    reconnectBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [reconnectBtn addTarget:self action:@selector(handleReconnect) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:reconnectBtn];

    // ── Contraintes Auto Layout ──
    [NSLayoutConstraint activateConstraints:@[
        // En-tête
        [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [closeBtn.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [closeBtn.widthAnchor constraintEqualToConstant:32],
        [closeBtn.heightAnchor constraintEqualToConstant:32],

        // Sep 1
        [sep1.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:14],
        [sep1.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [sep1.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [sep1.heightAnchor constraintEqualToConstant:1],

        // Wi-Fi
        [wifiHeader.topAnchor constraintEqualToAnchor:sep1.bottomAnchor constant:12],
        [wifiHeader.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

        [wifiExplain.topAnchor constraintEqualToAnchor:wifiHeader.bottomAnchor constant:4],
        [wifiExplain.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [wifiExplain.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [self.ipValueLabel.topAnchor constraintEqualToAnchor:wifiExplain.bottomAnchor constant:6],
        [self.ipValueLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

        [self.statusValueLabel.topAnchor constraintEqualToAnchor:self.ipValueLabel.bottomAnchor constant:4],
        [self.statusValueLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

        // Sep 2
        [sep2.topAnchor constraintEqualToAnchor:self.statusValueLabel.bottomAnchor constant:12],
        [sep2.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [sep2.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [sep2.heightAnchor constraintEqualToConstant:1],

        // Zoom & Affichage
        [zoomHeader.topAnchor constraintEqualToAnchor:sep2.bottomAnchor constant:12],
        [zoomHeader.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

        [self.zoomValueLabel.topAnchor constraintEqualToAnchor:zoomHeader.bottomAnchor constant:8],
        [self.zoomValueLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

        [self.resetZoomButton.centerYAnchor constraintEqualToAnchor:self.zoomValueLabel.centerYAnchor],
        [self.resetZoomButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [self.resetZoomButton.widthAnchor constraintEqualToConstant:165],
        [self.resetZoomButton.heightAnchor constraintEqualToConstant:30],

        [self.gravitySegment.topAnchor constraintEqualToAnchor:self.zoomValueLabel.bottomAnchor constant:10],
        [self.gravitySegment.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.gravitySegment.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [self.gravitySegment.heightAnchor constraintEqualToConstant:32],

        [gesturesTip.topAnchor constraintEqualToAnchor:self.gravitySegment.bottomAnchor constant:10],
        [gesturesTip.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [gesturesTip.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        // Sep 3
        [sep3.topAnchor constraintEqualToAnchor:gesturesTip.bottomAnchor constant:12],
        [sep3.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [sep3.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [sep3.heightAnchor constraintEqualToConstant:1],

        // Flux vidéo & Actions
        [statsHeader.topAnchor constraintEqualToAnchor:sep3.bottomAnchor constant:12],
        [statsHeader.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

        [self.statsValueLabel.topAnchor constraintEqualToAnchor:statsHeader.bottomAnchor constant:6],
        [self.statsValueLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

        [reconnectBtn.topAnchor constraintEqualToAnchor:self.statsValueLabel.bottomAnchor constant:12],
        [reconnectBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [reconnectBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [reconnectBtn.heightAnchor constraintEqualToConstant:34],
        [reconnectBtn.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18]
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.dimmedBackground.frame = self.bounds;

    CGFloat cardWidth = MIN(440, self.bounds.size.width - 40);
    // Auto-layout calcule la hauteur automatiquement
    self.cardView.bounds = CGRectMake(0, 0, cardWidth, 540);
    self.cardView.center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
}

// ─── Helpers d'éléments graphiques ───────────────────────────────────────────

- (UIView *)createSeparator {
    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    return sep;
}

- (UILabel *)createSectionHeader:(NSString *)title {
    UILabel *header = [[UILabel alloc] init];
    header.text = title;
    header.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    header.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    return header;
}

// ─── Actions Utilisateur ─────────────────────────────────────────────────────

- (void)handleResetZoom {
    if ([self.delegate respondsToSelector:@selector(settingsOverlayDidRequestResetZoom:)]) {
        [self.delegate settingsOverlayDidRequestResetZoom:self];
    }
}

- (void)handleGravityChange:(UISegmentedControl *)sender {
    AVLayerVideoGravity gravity = (sender.selectedSegmentIndex == 0)
        ? AVLayerVideoGravityResizeAspect
        : AVLayerVideoGravityResizeAspectFill;

    if ([self.delegate respondsToSelector:@selector(settingsOverlay:didChangeVideoGravity:)]) {
        [self.delegate settingsOverlay:self didChangeVideoGravity:gravity];
    }
}

- (void)handleReconnect {
    if ([self.delegate respondsToSelector:@selector(settingsOverlayDidRequestReconnect:)]) {
        [self.delegate settingsOverlayDidRequestReconnect:self];
    }
}

// ─── Mises à jour de télémétrie ──────────────────────────────────────────────

- (void)updateZoomScale:(CGFloat)scale {
    _currentZoom = scale;
    self.zoomValueLabel.text = [NSString stringWithFormat:@"Zoom : %.1fx (%.0f%%)", scale, scale * 100.0];
}

- (void)updateFPS:(NSUInteger)fps {
    self.statsValueLabel.text = [NSString stringWithFormat:@"FPS : %lu fps", (unsigned long)fps];
}

- (void)updateResolution:(CGSize)size {
    self.statsValueLabel.text = [NSString stringWithFormat:@"Résolution : %.0f × %.0f", size.width, size.height];
}

- (void)updateConnectionState:(NSString *)state isConnected:(BOOL)isConnected clientIP:(NSString *)clientIP {
    if (isConnected && clientIP.length > 0) {
        self.statusValueLabel.text = [NSString stringWithFormat:@"Statut : Connecté à %@", clientIP];
        self.statusValueLabel.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1.0];
    } else {
        self.statusValueLabel.text = [NSString stringWithFormat:@"Statut : %@", state ?: @"Déconnecté"];
        self.statusValueLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    }
}

- (void)setVideoGravity:(AVLayerVideoGravity)gravity {
    self.gravitySegment.selectedSegmentIndex = [gravity isEqualToString:AVLayerVideoGravityResizeAspectFill] ? 1 : 0;
}

// ─── Présentation / Fermeture ────────────────────────────────────────────────

- (void)showInView:(UIView *)parentView {
    self.frame = parentView.bounds;
    self.alpha = 0.0;
    self.cardView.transform = CGAffineTransformMakeScale(0.85, 0.85);

    // Rafraîchir l'adresse IP Wi-Fi à chaque ouverture
    NSString *ip = [SettingsOverlayView localWiFiIPAddress];
    self.ipValueLabel.text = [NSString stringWithFormat:@"%@:7000", ip];

    [parentView addSubview:self];

    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
        self.alpha = 1.0;
        self.cardView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0.0;
        self.cardView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if ([self.delegate respondsToSelector:@selector(settingsOverlayDidDismiss:)]) {
            [self.delegate settingsOverlayDidDismiss:self];
        }
    }];
}

@end
