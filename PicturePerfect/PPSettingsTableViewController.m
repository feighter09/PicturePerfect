//
//  PicturePerfectSettingsViewController.m
//  PicturePerfect
//
//  Created by Austin Feight on 2/17/14.
//
//

#import "PPSettingsTableViewController.h"

@interface PPSettingsTableViewController ()

@end

@implementation PPSettingsTableViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)accuracySwitched:(id)sender {
  [_delegate accuracySwitched:sender];
}

- (IBAction)smileSwitched:(id)sender {
  [_delegate smileSwitched:sender];
}

- (IBAction)eyesOpenSwitched:(id)sender {
  [_delegate eyesOpenSwitched:sender];
}

- (IBAction)done:(id)sender {
  [self dismissViewControllerAnimated:YES completion:nil];
}
@end
