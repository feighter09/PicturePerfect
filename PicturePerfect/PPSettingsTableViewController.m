//
//  PicturePerfectSettingsViewController.m
//  PicturePerfect
//
//  Created by Austin Feight on 2/17/14.
//
//

#import "PPSettingsTableViewController.h"

@interface PPSettingsTableViewController ()

@property (nonatomic) BOOL expanded;
@property (strong, nonatomic) IBOutlet UITableViewCell *info1;
@property (strong, nonatomic) IBOutlet UITableViewCell *info2;
@property (strong, nonatomic) IBOutlet UITableViewCell *info3;
@property (strong, nonatomic) IBOutlet UITableViewCell *expandContractCell;
@property (strong, nonatomic) IBOutlet UIButton *expandContractButton;
@property (nonatomic) CGRect info1Rect;
@property (nonatomic) CGRect info2Rect;
@property (nonatomic) CGRect info3Rect;
- (IBAction)expandOrContract:(id)sender;

@end

@implementation PPSettingsTableViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  _expanded = YES;
  _info1Rect = [_info1 frame];
  _info2Rect = [_info2 frame];
  _info3Rect = [_info3 frame];
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

- (IBAction)expandOrContract:(id)sender {
  if (_expanded) {
    [self contractCells];
    NSArray *indexes = @[[NSIndexPath indexPathForRow:0 inSection:0], [NSIndexPath indexPathForRow:1 inSection:0], [NSIndexPath indexPathForRow:2 inSection:0]];
    [self.tableView reloadRowsAtIndexPaths:indexes
                          withRowAnimation:UITableViewRowAnimationFade];
    _expanded = !_expanded;
  } else {
    [self expandCells];
    _expanded = !_expanded;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0], [NSIndexPath indexPathForRow:1 inSection:0], [NSIndexPath indexPathForRow:2 inSection:0]]
                          withRowAnimation:UITableViewRowAnimationFade];
  }
  [self refreshControl];
  [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  
  switch (section) {
    case 0:
      if (_expanded)
        return 4;
      else
        return 4;
    case 1:
      return 3;
    case 2:
      return 1;
  }
  
  return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  switch (indexPath.section) {
    case 0:
      if (_expanded) {
        if (indexPath.row == 0)
          return 82.f;
        else if (indexPath.row == 1)
          return 72.f;
        else if (indexPath.row == 2)
          return 46.f;
        else
          return 44.f;
      } else {
        if (indexPath.row == 0)
          return 0.f;
        else if (indexPath.row == 1)
          return 0.f;
        else if (indexPath.row == 2)
          return 0.f;
        else
          return 44.f;
      }
    case 1:
      if (indexPath.row == 0)
        return 66.f;
      else
        return 44.f;
    case 2:
      return 44.f;
  }
  
  return 0;
}

- (void)contractCells {
  CGRect oldFrame = [_info1 frame];
  CGRect hiddenRect = CGRectMake(oldFrame.origin.x,
                                 oldFrame.origin.y,
                                 oldFrame.size.width,
                                 0);
  [_info1 setFrame:hiddenRect];
  [_info2 setFrame:hiddenRect];
  [_info3 setFrame:hiddenRect];
  [_expandContractButton setTitle:@"Expand" forState:UIControlStateNormal];
}

- (void)expandCells {
  CGRect oldFrame = [_expandContractCell frame];
  [_info1 setFrame:CGRectMake(oldFrame.origin.x, oldFrame.origin.y, oldFrame.size.width, 84.f)];
  [_info2 setFrame:_info2Rect];
  [_info3 setFrame:_info3Rect];
  [_expandContractButton setTitle:@"Contract" forState:UIControlStateNormal];
}
@end
