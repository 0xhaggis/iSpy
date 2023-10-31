//
//  FloatingButtonWindow.m
//  envdump
//
//  Created by Carl on 2/26/18.
//  Copyright © 2018 Carl. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "iSpy.class.h"
#include "iSpy.common.h"
#include "iSpy.FloatingButtonWindow.h"

@interface FloatingButtonWindow ()
    
@end
@implementation FloatingButtonWindow

-(id)init {
    self = [super init];
    [self setBackgroundColor:nil];
    return self;
}
    
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    //NSLog(@"pointInside: %f,%f   //   %@", point.x, point.y, event);
    CGPoint p = [self convertPoint:point toView:self.button];
    //NSLog(@"pointInside: %f,%f   //   %@", p.x, p.y, event);
    BOOL yn = [self.button pointInside:p withEvent:event];
    if(!yn) {
        p = [self convertPoint:point toView:self.popController.sourceView];
        yn = [self.popController.sourceView pointInside:p withEvent:event];
    }
    
    if(yn) {
        NSLog(@"Inside button");
    }
    return yn;
}
    
@end
