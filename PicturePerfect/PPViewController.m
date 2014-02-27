#import "PPViewController.h"
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "PPImageProcessing.h"

@implementation PPViewController

#pragma mark - Setup / Teardown / Start

- (void)setupAVCapture
{
	NSError *error = nil;
	
	AVCaptureSession *session = [AVCaptureSession new];
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
	    [session setSessionPreset:AVCaptureSessionPreset640x480];
	else
	    [session setSessionPreset:AVCaptureSessionPresetPhoto];
	
  // Select a video device, make an input
	AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	
  _isUsingFrontFacingCamera = NO;
	if ( [session canAddInput:deviceInput] )
		[session addInput:deviceInput];
	
  // Make a still image output
	_stillImageOutput = [AVCaptureStillImageOutput new];
	[_stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:(__bridge void *)(AVCaptureStillImageIsCapturingStillImageContext)];
	if ( [session canAddOutput:_stillImageOutput] )
		[session addOutput:_stillImageOutput];
	
  // Make a video data output
	_videoDataOutput = [AVCaptureVideoDataOutput new];
	
  // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
	NSDictionary *rgbOutputSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCMPixelFormat_32BGRA]};
	[_videoDataOutput setVideoSettings:rgbOutputSettings];
	[_videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked (as we process the still image)
    
  // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
  // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
  // see the header doc for setSampleBufferDelegate:queue: for more information
	_videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
	[_videoDataOutput setSampleBufferDelegate:self queue:_videoDataOutputQueue];
	
  if ( [session canAddOutput:_videoDataOutput] )
		[session addOutput:_videoDataOutput];
	[[_videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:NO];
	
	_effectiveScale = 1.0;
	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
	[_previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
	[_previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
	CALayer *rootLayer = [_previewView layer];
	[rootLayer setMasksToBounds:YES];
	[_previewLayer setFrame:[rootLayer bounds]];
	[rootLayer addSublayer:_previewLayer];
	[session startRunning];
}

// clean up capture setup
- (void)teardownAVCapture
{
	[_stillImageOutput removeObserver:self forKeyPath:@"isCapturingStillImage"];
	[_previewLayer removeFromSuperlayer];
}

- (void)dealloc
{
	[self teardownAVCapture];
}

// turn on/off face detection
- (void)toggleFaceDetection:(BOOL)on
{
	_detectFaces = on;
	[[_videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:_detectFaces];
	if (!_detectFaces) {
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			// clear out any squares currently displaying.
			[self drawFaceBoxesForFeatures:[NSArray array] forVideoBox:CGRectZero orientation:UIDeviceOrientationPortrait];
		});
	}
}

#pragma mark - Util

// perform a flash bulb animation using KVO to monitor the value of the capturingStillImage property of the AVCaptureStillImageOutput class
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
	if ( context == (__bridge void *)(AVCaptureStillImageIsCapturingStillImageContext) ) {
		BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		
		if ( isCapturingStillImage ) {
			// do flash bulb like animation
			_flashView = [[UIView alloc] initWithFrame:[_previewView frame]];
			[_flashView setBackgroundColor:[UIColor whiteColor]];
			[_flashView setAlpha:0.f];
			[self.view.window addSubview:_flashView];
			
			[UIView animateWithDuration:.4f
							 animations:^{
								 [_flashView setAlpha:1.f];
							 }
			 ];
		} else {
			[UIView animateWithDuration:.4f
         animations:^{
           [_flashView setAlpha:0.f];
         }
         completion:^(BOOL finished){
           [_flashView removeFromSuperview];
           _flashView = nil;
         }
			 ];
		}
	}
}

// utility routing used during image capture to set up capture orientation
- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
	if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
		return AVCaptureVideoOrientationLandscapeRight;
	else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
		return AVCaptureVideoOrientationLandscapeLeft;
  return (AVCaptureVideoOrientation) deviceOrientation;
}

// utility routine used after taking a still image to write the resulting image to the camera roll
- (BOOL)writeCGImageToCameraRoll:(CGImageRef)cgImage withMetadata:(NSDictionary *)metadata
{
	CFMutableDataRef destinationData = CFDataCreateMutable(kCFAllocatorDefault, 0);
	CGImageDestinationRef destination = CGImageDestinationCreateWithData(destinationData, 
																		 CFSTR("public.jpeg"), 
																		 1, 
																		 NULL);
	BOOL success = (destination != NULL);

	const float JPEGCompQuality = 0.85f; // JPEGHigherQuality
	CFMutableDictionaryRef optionsDict = NULL;
	CFNumberRef qualityNum = NULL;
	
	qualityNum = CFNumberCreate(0, kCFNumberFloatType, &JPEGCompQuality);    
	if ( qualityNum ) {
		optionsDict = CFDictionaryCreateMutable(0, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		if ( optionsDict )
			CFDictionarySetValue(optionsDict, kCGImageDestinationLossyCompressionQuality, qualityNum);
		CFRelease( qualityNum );
	}
	
	CGImageDestinationAddImage( destination, cgImage, optionsDict );
	success = CGImageDestinationFinalize( destination );

	if ( optionsDict )
		CFRelease(optionsDict);
		
	CFRetain(destinationData);
	ALAssetsLibrary *library = [ALAssetsLibrary new];
	[library writeImageDataToSavedPhotosAlbum:(__bridge id)destinationData metadata:metadata completionBlock:^(NSURL *assetURL, NSError *error) {
		if (destinationData)
			CFRelease(destinationData);
	}];

  return success;
}

// utility routine to display error aleart if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		[[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
                                message:[error localizedDescription]
                               delegate:nil
                      cancelButtonTitle:@"Dismiss"
                      otherButtonTitles:nil] show];
	});
}

// use front/back camera
- (void)switchCameras
{
	AVCaptureDevicePosition desiredPosition;
	if (_isUsingFrontFacingCamera)
		desiredPosition = AVCaptureDevicePositionBack;
	else
		desiredPosition = AVCaptureDevicePositionFront;
  
  BOOL found = NO;
	for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
		if ([d position] == desiredPosition) {
			[_previewLayer.session beginConfiguration];
			AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:d error:nil];
			for (AVCaptureInput *oldInput in [_previewLayer.session inputs]) {
				[_previewLayer.session removeInput:oldInput];
			}
			[_previewLayer.session addInput:input];
			[_previewLayer.session commitConfiguration];
      found = YES;
			break;
		}
	}
  
  if (found) {
    _isUsingFrontFacingCamera = (desiredPosition == AVCaptureDevicePositionFront);
  } else {
    [_hud setDetailsLabelText:@"I tried really hard but another camera is not available."];
    [_hud show:YES];
    [_hud hide:YES afterDelay:5];
  }
}

#pragma mark - Still Picture

// main action method to take a still image -- if face detection has been turned on and a face has been detected
// the square overlay will be composited on top of the captured image and saved to the camera roll
- (IBAction)openPhotos:(id)sender {
  if ([UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
    UIImagePickerController *imagePicker = [UIImagePickerController new];
    [imagePicker setDelegate:self];
    [imagePicker setSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    [imagePicker setAllowsEditing:NO];
    [self presentViewController:imagePicker
                       animated:YES
                     completion:nil];
  }
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary *)info {
  NSURL *imageUrl = [info objectForKey:UIImagePickerControllerMediaURL];
  UIImage *image = [UIImage imageWithContentsOfFile:[imageUrl path]];
  
  
}

- (IBAction)takePicture:(id)sender
{
  _takingPicture = YES;

  if (_checkSmile) {
    [_hud setDetailsLabelText:@"Smile, bitches!"];
  } else {
    [_hud setDetailsLabelText:@"Find a face!"];
  }
  [_hud show:YES];
}

- (void)actuallyTakePicture {
  
  [_hud hide:YES];
  if (!_takingPicture)
    return;

  _takingPicture = NO;

	AVCaptureConnection *stillImageConnection = [_stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
	UIDeviceOrientation curDeviceOrientation = [UIDevice.currentDevice orientation];
	AVCaptureVideoOrientation avcaptureOrientation = [self avOrientationForDeviceOrientation:curDeviceOrientation];
	[stillImageConnection setVideoOrientation:avcaptureOrientation];
	[stillImageConnection setVideoScaleAndCropFactor:_effectiveScale];
	
  BOOL doingFaceDetection = _detectFaces && (_effectiveScale == 1.0);

  // set the appropriate pixel format / image type output setting depending on if we'll need an uncompressed image for
  // the possiblity of drawing the red square over top or if we're just writing a jpeg to the camera roll which is the trival case
  if (doingFaceDetection)
		[_stillImageOutput setOutputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCMPixelFormat_32BGRA]}];
	else
		[_stillImageOutput setOutputSettings:@{AVVideoCodecKey: AVVideoCodecJPEG}];
	
	[_stillImageOutput captureStillImageAsynchronouslyFromConnection:stillImageConnection
		completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
			if (error) {
				[self displayErrorOnMainQueue:error withMessage:@"Take picture failed"];
			} else {
				if (doingFaceDetection) {
					NSDictionary *imageOptions = nil;
					NSNumber *orientation = (__bridge NSNumber *)(CMGetAttachment(imageDataSampleBuffer, kCGImagePropertyOrientation, NULL));
					if (orientation)
						imageOptions = @{CIDetectorImageOrientation: orientation};
					
          // when processing an existing frame we want any new frames to be automatically dropped
          // queueing this block to execute on the videoDataOutputQueue serial queue ensures this
          // see the header doc for setSampleBufferDelegate:queue: for more information
          dispatch_sync(_videoDataOutputQueue, ^(void) {
            // get the array of CIFeature instances in the given image with a orientation passed in
            // the detection will be done based on the orientation but the coordinates in the returned features will
            // still be based on those of the image.
						CGImageRef srcImage = NULL;
						OSStatus err = CreateCGImageFromCVPixelBuffer(CMSampleBufferGetImageBuffer(imageDataSampleBuffer), &srcImage);
						check(!err);
            UIImageWriteToSavedPhotosAlbum([[UIImage imageWithCGImage:srcImage] imageRotatedByDegrees:90], nil, nil, nil);

            if (srcImage)
							CFRelease(srcImage);
						
						CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
            if (attachments)
							CFRelease(attachments);
					});
				} else {
					NSData *jpegData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
					CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
					ALAssetsLibrary *library = [ALAssetsLibrary new];
					[library writeImageDataToSavedPhotosAlbum:jpegData
                                           metadata:(__bridge id)attachments
                                    completionBlock:^(NSURL *assetURL, NSError *error) {
						if (error) {
							[self displayErrorOnMainQueue:error
                                withMessage:@"Save to camera roll failed"];
						}
					}];
					
					if (attachments)
						CFRelease(attachments);
				}
			}
		}
	 ];
}

// find where the video box is positioned within the preview layer based on the video size and gravity
+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity
                          frameSize:(CGSize)frameSize
                       apertureSize:(CGSize)apertureSize {
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
	
	CGRect videoBox;
	videoBox.size = size;
	if (size.width < frameSize.width)
		videoBox.origin.x = (frameSize.width - size.width) / 2;
	else
		videoBox.origin.x = (size.width - frameSize.width) / 2;
	
	if ( size.height < frameSize.height )
		videoBox.origin.y = (frameSize.height - size.height) / 2;
	else
		videoBox.origin.y = (size.height - frameSize.height) / 2;
    
	return videoBox;
}

#pragma mark - Face processing

- (void)accuracySwitched:(id)sender {
  NSDictionary *detectorOptions;
  if ([(UISegmentedControl *)sender selectedSegmentIndex] == 0) {
    detectorOptions = @{CIDetectorAccuracy: CIDetectorAccuracyLow};
  } else {
    detectorOptions = @{CIDetectorAccuracy: CIDetectorAccuracyHigh};
  }
	_faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace
                                     context:nil
                                     options:detectorOptions];
}
- (void)smileSwitched:(id)sender {
  _checkSmile = [(UISwitch *)sender isOn];
}
- (void)eyesOpenSwitched:(id)sender {
  _checkEyesOpen = [(UISwitch *)sender isOn];
}

- (void)drawFaceBoxesForFeatures:(NSArray *)features
                     forVideoBox:(CGRect)clap
                     orientation:(UIDeviceOrientation)orientation
{
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	// hide all the face layers
	for ( CALayer *layer in [_previewLayer sublayers] ) {
		if ( [[layer name] isEqualToString:@"FaceLayer"] )
			[layer setHidden:YES];
	}	
	
	if ( ![features count] || !_detectFaces ) {
		[CATransaction commit];
		return; // early bail.
	}
		
	CGSize parentFrameSize = [_previewView frame].size;
	NSString *gravity = [_previewLayer videoGravity];
	BOOL isMirrored = [_previewLayer.connection isVideoMirrored];
	CGRect previewBox = [PPViewController videoPreviewBoxForGravity:gravity
                                                        frameSize:parentFrameSize
                                                     apertureSize:clap.size];
  [self clearBoxLayers];
	BOOL goodPicture = YES;
	for ( CIFaceFeature *ff in features ) {
		CGRect faceRect = [ff bounds];

		CGFloat temp = faceRect.size.width;
		faceRect.size.width = faceRect.size.height;
		faceRect.size.height = temp;
		temp = faceRect.origin.x;
		faceRect.origin.x = faceRect.origin.y;
		faceRect.origin.y = temp;

		CGFloat widthScaleBy = previewBox.size.width / clap.size.height;
		CGFloat heightScaleBy = previewBox.size.height / clap.size.width;
		faceRect.size.width *= widthScaleBy;
		faceRect.size.height *= heightScaleBy;
		faceRect.origin.x *= widthScaleBy;
		faceRect.origin.y *= heightScaleBy;

		if ( isMirrored )
			faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y);
		else
			faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
		
		CALayer *featureLayer = nil;
//		// re-use an existing layer if possible
//		while ( !featureLayer && (currentSublayer < sublayersCount) ) {
//			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
//			if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
//				featureLayer = currentLayer;
//				[currentLayer setHidden:NO];
//			}
//		}
		
		// decided to throw away all the old layers at each frame because it was difficult to
    // reuse layers. try keeping around an available queue of red and green boxes
		if ( featureLayer ) {
      [featureLayer removeFromSuperlayer];
    }
    featureLayer = [CALayer new];
    if ([self pictureChecks:ff]) {
      [featureLayer setContents:(id)[_greenSquare CGImage]];
    } else {
      [featureLayer setContents:(id)[_redSquare CGImage]];
      goodPicture = NO;
    }
    [featureLayer setName:@"FaceLayer"];
    [_previewLayer addSublayer:featureLayer];
		[featureLayer setFrame:faceRect];
    if (_takingPicture && goodPicture) {
      dispatch_async(_videoDataOutputQueue, ^{
        [self actuallyTakePicture];
      });
    }
		
		switch (orientation) {
			case UIDeviceOrientationPortrait:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
				break;
			case UIDeviceOrientationPortraitUpsideDown:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
				break;
			case UIDeviceOrientationLandscapeLeft:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
				break;
			case UIDeviceOrientationLandscapeRight:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
				break;
			case UIDeviceOrientationFaceUp:
			case UIDeviceOrientationFaceDown:
			default:
				break; // leave the layer in its last known orientation
		}
	}
	
	[CATransaction commit];
}

- (void)clearBoxLayers {
  NSMutableArray *save = [[NSMutableArray alloc] init];
  [_previewLayer.sublayers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    if ([[(CALayer *)(obj) name] isEqualToString:@"FaceLayer"])
      [save addObject:obj];
  }];
  [save enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    [(CALayer *)obj removeFromSuperlayer];
  }];
}

- (BOOL)pictureChecks:(CIFaceFeature *)ff {
  if (_checkSmile) {
    if (![ff hasSmile]) {
      return NO;
    }
  }
  
  if (_checkEyesOpen) {
    if ([ff hasLeftEyePosition] && [ff leftEyeClosed]) {
      return NO;
    } else if ([ff hasRightEyePosition] && [ff rightEyeClosed]) {
      return NO;
    }
  }
  
  return YES;
}
         
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{	
	// got an image
	CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
	CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(__bridge NSDictionary *)attachments];
	if (attachments)
		CFRelease(attachments);
	UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
	int exifOrientation;
	
  /* kCGImagePropertyOrientation values
      The intended display orientation of the image. If present, this key is a CFNumber value with the same value as defined
      by the TIFF and EXIF specifications -- see enumeration of integer constants. 
      The value specified where the origin (0,0) of the image is located. If not present, a value of 1 is assumed.

      used when calling featuresInImage: options: The value for this key is an integer NSNumber from 1..8 as found in kCGImagePropertyOrientation.
      If present, the detection will be done based on that orientation but the coordinates in the returned features will still be based on those of the image. */
  
	enum {
		PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
		PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2, //   2  =  0th row is at the top, and 0th column is on the right.  
		PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.  
		PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.  
		PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.  
		PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.  
		PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.  
		PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.  
	};
	
	switch (curDeviceOrientation) {
		case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
			exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
			break;
		case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
			if (_isUsingFrontFacingCamera)
				exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
			else
				exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
			break;
		case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
			if (_isUsingFrontFacingCamera)
				exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
			else
				exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
			break;
		case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
		default:
			exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
			break;
	}

	NSDictionary *imageOptions = @{
                                 CIDetectorSmile: @(YES),
                                 CIDetectorEyeBlink: @(YES),
                                 CIDetectorImageOrientation: [NSNumber numberWithInt:exifOrientation]
                                };
	NSArray *features = [_faceDetector featuresInImage:ciImage options:imageOptions];

  // get the clean aperture
  // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
  // that represents image data valid for display.
	CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
	CGRect clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);
	
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		[self drawFaceBoxesForFeatures:features forVideoBox:clap orientation:curDeviceOrientation];
	});
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
  [super viewDidLoad];
	[self setupAVCapture];
  
  _settings = [self.storyboard instantiateViewControllerWithIdentifier:@"Settings"];
  [_settings setDelegate:self];
  [_settings setModalTransitionStyle:UIModalTransitionStyleFlipHorizontal];
  _checkSmile = NO;
  _checkEyesOpen = NO;
  
	_redSquare = [UIImage imageNamed:@"redSquarePNG"];
  _greenSquare = [UIImage imageNamed:@"greenSquarePNG"];
  
	NSDictionary *detectorOptions = @{CIDetectorAccuracy: CIDetectorAccuracyLow};
	_faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace
                                    context:nil
                                    options:detectorOptions];
  [self toggleFaceDetection:YES];
  
  _hud = [[MBProgressHUD alloc] initWithView:self.view];
  [_hud setMode:MBProgressHUDModeText];
  [_hud setYOffset:100.f];
  [self.view addSubview:_hud];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
	if ( [gestureRecognizer isKindOfClass:UIPinchGestureRecognizer.class] ) {
		_beginGestureScale = _effectiveScale;
	}
	return YES;
}

// scale image depending on users pinch gesture
- (IBAction)handlePinchGesture:(UIPinchGestureRecognizer *)recognizer
{
	BOOL allTouchesAreOnThePreviewLayer = YES;
	NSUInteger numTouches = [recognizer numberOfTouches], i;
	for ( i = 0; i < numTouches; ++i ) {
		CGPoint location = [recognizer locationOfTouch:i inView:_previewView];
		CGPoint convertedLocation = [_previewLayer convertPoint:location fromLayer:_previewLayer.superlayer];
		if ( ! [_previewLayer containsPoint:convertedLocation] ) {
			allTouchesAreOnThePreviewLayer = NO;
			break;
		}
	}
	
	if ( allTouchesAreOnThePreviewLayer ) {
		_effectiveScale = _beginGestureScale * recognizer.scale;
		if (_effectiveScale < 1.0)
			_effectiveScale = 1.0;
		CGFloat maxScaleAndCropFactor = [[_stillImageOutput connectionWithMediaType:AVMediaTypeVideo] videoMaxScaleAndCropFactor];
		if (_effectiveScale > maxScaleAndCropFactor)
			_effectiveScale = maxScaleAndCropFactor;
		[CATransaction begin];
		[CATransaction setAnimationDuration:.025];
		[_previewLayer setAffineTransform:CGAffineTransformMakeScale(_effectiveScale, _effectiveScale)];
		[CATransaction commit];
	}
}

- (void)handleTapGesture:(UIGestureRecognizer *)sender {
  [self switchCameras];
}

- (IBAction)showSettings:(id)sender {
  [self presentViewController:_settings
                     animated:YES
                   completion:nil];
}

@end
