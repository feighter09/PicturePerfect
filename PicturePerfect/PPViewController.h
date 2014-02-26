#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "PPSettingsTableViewController.h"
@class CIDetector;

@interface PPViewController : UIViewController <UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, PPSettingsDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic) BOOL detectFaces;
@property (nonatomic) BOOL isUsingFrontFacingCamera;
@property (nonatomic) BOOL checkSmile;
@property (nonatomic) BOOL checkEyesOpen;
@property (nonatomic) BOOL takingPicture;

@property (strong, nonatomic) IBOutlet UIView *previewView;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (strong, nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (strong, nonatomic) dispatch_queue_t videoDataOutputQueue;
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (strong, nonatomic) UIView *flashView;

@property (strong, atomic) CIDetector *faceDetector;
@property (strong, nonatomic) UIImage *redSquare, *greenSquare;
@property (strong, nonatomic) PPSettingsTableViewController *settings;

@property (nonatomic) CGFloat beginGestureScale;
@property (nonatomic) CGFloat effectiveScale;

- (IBAction)openPhotos:(id)sender;
- (IBAction)takePicture:(id)sender;
- (void)switchCameras;
- (IBAction)handlePinchGesture:(UIGestureRecognizer *)sender;
- (IBAction)showSettings:(id)sender;

// settings delegate fcns
- (IBAction)accuracySwitched:(id)sender;
- (IBAction)smileSwitched:(id)sender;
- (IBAction)eyesOpenSwitched:(id)sender;

@end
