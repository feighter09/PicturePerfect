//
//  PicturePerfectSettingsViewController.h
//  PicturePerfect
//
//  Created by Austin Feight on 2/17/14.
//
//

#import <UIKit/UIKit.h>

@protocol PPSettingsDelegate <NSObject>

- (IBAction)accuracySwitched:(id)sender;
- (IBAction)smileSwitched:(id)sender;
- (IBAction)eyesOpenSwitched:(id)sender;

@end

@interface PPSettingsTableViewController : UITableViewController

@property (strong, nonatomic) id<PPSettingsDelegate> delegate;

- (IBAction)accuracySwitched:(id)sender;
- (IBAction)smileSwitched:(id)sender;
- (IBAction)eyesOpenSwitched:(id)sender;

- (IBAction)done:(id)sender;

@end
