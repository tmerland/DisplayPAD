// AppDelegate.m — Implémentation du délégué principal de DisplayPAD

#import "AppDelegate.h"
#import "DisplayViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Désactiver le verrouillage veille — l'écran reste allumé en permanence
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];

    // Créer la fenêtre plein écran avec fond noir
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];

    // Instancier le contrôleur de vue principal
    self.displayVC = [[DisplayViewController alloc] init];
    self.window.rootViewController = self.displayVC;

    [self.window makeKeyAndVisible];

    NSLog(@"[DisplayPAD] Application démarrée");
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Démarrer le récepteur TCP si ce n'est pas déjà fait
    // Le démarrage est géré dans DisplayViewController.viewDidLoad,
    // mais on s'assure ici qu'il est bien actif.
    NSLog(@"[DisplayPAD] Application active");
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // On reste actif intentionnellement (pas de pause du récepteur)
    NSLog(@"[DisplayPAD] Application en arrière-plan — récepteur maintenu actif");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"[DisplayPAD] Entrée en arrière-plan");
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    NSLog(@"[DisplayPAD] Retour au premier plan");
}

- (void)applicationWillTerminate:(UIApplication *)application {
    NSLog(@"[DisplayPAD] Arrêt de l'application");
}

@end
