// AppDelegate.h — Délégué principal de l'application DisplayPAD

#import <UIKit/UIKit.h>

@class DisplayViewController;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

/// Fenêtre principale de l'application (plein écran, fond noir)
@property (strong, nonatomic) UIWindow *window;

/// Contrôleur de vue principal gérant l'affichage H.264
@property (strong, nonatomic) DisplayViewController *displayVC;

@end
