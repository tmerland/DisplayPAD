// DisplayViewController.h — Contrôleur d'affichage H.264 (AVSampleBufferDisplayLayer)

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>
#import "TCPReceiver.h"

@interface DisplayViewController : UIViewController <TCPReceiverDelegate>

/// Couche vidéo plein écran (décodage matériel H.264 natif sur A7+)
@property (nonatomic, strong) AVSampleBufferDisplayLayer *displayLayer;

/// Récepteur TCP gérant le protocole DisplayPAD
@property (nonatomic, strong) TCPReceiver *receiver;

/// Session de décompression VideoToolbox (réservé pour usage futur)
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;

@end
