//
//  FloatingButtonWindow.h
//  envdump
//
//  Created by Carl on 2/26/18.
//  Copyright © 2018 Carl. All rights reserved.
//

#ifndef FloatingButtonWindow_h
#define FloatingButtonWindow_h
#import <UIKit/UIKit.h>

@interface FloatingButtonWindow : UIWindow
@property (retain) UIButton *button;
@property (retain) UIPopoverPresentationController *popController;
@end

#endif /* FloatingButtonWindow_h */
