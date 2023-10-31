//
//  iSpyViewController.h
//  envdump
//
//  Created by Carl on 2/25/18.
//  Copyright © 2018 Carl. All rights reserved.
//

#ifndef iSpyHoverButton_h
#define iSpyHoverButton_h

#import <UIKit/UIKit.h>
#import "iSpy.FloatingButtonWindow.h"

@interface iSpyHoverButton : UIViewController <UIGestureRecognizerDelegate, UIPopoverPresentationControllerDelegate, UITableViewDataSource, UITableViewDelegate>
@property (retain) FloatingButtonWindow *window;
@property (retain) UIViewController *rootVC;
@property (retain) UIViewController *popControllerVC;
@property (retain) UIPopoverPresentationController *popController;

// BF button always floats on top
@property (retain) UIButton *buttonBF;

// These are on the popover
@property (retain) UIButton *buttonDumpDecrypted;
@property (retain) UISwitch *switchSSLPinning;
@property (retain) UISwitch *switchCycript;
@property (retain) UISwitch *switchAPI;

@end

#endif /* iSpyHoverButton */
