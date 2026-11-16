// SettingsOverlayView.h — Menu réglages iPad pour DisplayPAD (geste à 3 doigts)
//
// Interface modale semi-transparente affichant les informations réseau (IP Wi-Fi),
// les réglages de zoom, le mode d'affichage vidéo et la télémétrie.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class SettingsOverlayView;

@protocol SettingsOverlayDelegate <NSObject>
@optional
- (void)settingsOverlayDidRequestResetZoom:(SettingsOverlayView *)overlay;
- (void)settingsOverlay:(SettingsOverlayView *)overlay didChangeVideoGravity:(AVLayerVideoGravity)gravity;
- (void)settingsOverlayDidRequestReconnect:(SettingsOverlayView *)overlay;
- (void)settingsOverlayDidDismiss:(SettingsOverlayView *)overlay;
@end

@interface SettingsOverlayView : UIView

@property (nonatomic, weak) id<SettingsOverlayDelegate> delegate;

/// Met à jour la télémétrie affichée
- (void)updateZoomScale:(CGFloat)scale;
- (void)updateFPS:(NSUInteger)fps;
- (void)updateResolution:(CGSize)size;
- (void)updateConnectionState:(NSString *)state isConnected:(BOOL)isConnected clientIP:(NSString *)clientIP;
- (void)setVideoGravity:(AVLayerVideoGravity)gravity;

/// Affiche l'overlay avec une animation fluide
- (void)showInView:(UIView *)parentView;

/// Masque l'overlay
- (void)dismiss;

@end
