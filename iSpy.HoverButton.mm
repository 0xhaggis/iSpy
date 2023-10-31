//
//  iSpyViewController.m
//  envdump
//
//  Created by Carl on 2/25/18.
//  Copyright © 2018 Carl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include "iSpy.class.h"
#include "iSpy.common.h"
#import "iSpy.HoverButton.h"
#import "iSpy.FloatingButtonWindow.h"

#define ALPHA_VALUE 0.4

const char *BFLogoPNG = 
"\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x48\x00\x00\x00\x35\x08\x06\x00\x00\x00\xe2" \
"\x51\xad\x58\x00\x00\x00\x01\x73\x52\x47\x42\x00\xae\xce\x1c\xe9\x00\x00\x04\x8f\x49\x44\x41\x54\x68\x05\xed\x9a\x5f\x88" \
"\x54\x55\x1c\xc7\xbf\xe7\xde\x3b\x73\x67\xee\xec\xe2\x9f\xcd\x76\xb3\xdc\x42\x0d\xd4\xb0\x7f\x68\x44\x89\x50\xd4\x42\x60" \
"\x60\x49\x10\x2a\xab\x56\x14\x12\x95\x96\xb5\xba\x51\x41\xfe\xc1\x45\x57\x7d\x50\x0a\x02\xf3\xa1\x87\x1e\xf6\xc5\x48\x29" \
"\x22\x2a\xc4\x87\xc2\x1e\xea\x25\xa2\x3f\x24\x3e\x28\x11\x51\xa1\x33\x6c\xb3\x33\xb7\xdf\x99\x76\x69\xe6\xce\x39\xf7\xcc" \
"\xbd\xf7\xdc\x99\x91\xce\x41\xd9\xb9\xbf\xbf\xe7\xf7\xb9\xff\xce\xf9\x71\x01\x33\x0c\x01\x43\xc0\x10\x30\x04\x0c\x81\xab" \
"\x95\x00\x0b\x4e\xbc\x78\x6c\xb7\x3f\x79\xea\xfd\xa0\x38\xd5\x63\x6f\xeb\x28\xb2\x6b\xd6\xb7\x9e\x63\xaa\x8c\xcb\x3b\x37" \
"\x63\xea\xbb\x6f\x5a\xf7\x69\xc1\xd2\x59\xbe\x12\xbd\x63\x27\x1a\x98\x58\x41\xbf\xfc\xd3\x23\x70\x96\xdc\x16\x14\xa7\x7a" \
"\x5c\x7a\xe7\x00\x2a\xdf\x7f\xdb\x72\x8e\xd2\xf1\x71\xed\x70\xac\xbe\x7e\x14\x76\x1e\x6c\x9a\x43\x13\x20\x38\x19\x14\x76" \
"\x1d\x82\x35\xbb\xaf\xc9\x38\x2d\x81\x4f\x57\xc4\x95\xfd\x2f\xc1\xff\xeb\x0f\x65\x8a\xf2\xd9\x4f\x30\x79\xf2\x3d\xa5\x5d" \
"\x14\x03\x56\xab\x79\x1c\x4c\x50\x73\x33\x20\x8a\xcc\xae\xe9\x87\x37\x72\x00\xcc\xb6\xa3\xe4\x49\x64\x5b\xfd\xf5\x22\x8a" \
"\x07\x47\x42\x63\xf8\xbf\x5d\x42\xf1\xc8\x6b\xa1\x36\x71\x94\xf9\xa7\x5e\x86\xbd\xf4\x76\xa1\xab\x10\x10\xb7\x74\x6e\xbd" \
"\x0b\xb9\x4d\xdb\x84\x4e\x69\x09\xcb\x5f\x9f\x05\x4a\x57\xa4\xe1\x2b\xbf\xfc\x00\xbf\x78\x59\xaa\x8f\xa3\xc8\xde\xb7\x06" \
"\xd9\x87\xe5\xcf\x3f\x29\x20\x9e\xcc\x5d\xb7\x05\xd9\x7b\x1f\x8c\x93\xf7\xaa\xf0\xb1\x6f\xba\x19\xde\x73\x6f\x84\xce\x35" \
"\x14\x10\xf7\xf4\xb6\xef\x81\xbd\x60\x61\x68\x10\xbd\xca\x86\x97\x48\x63\x68\x16\xa2\x6b\xb4\x54\x1e\xb1\x42\x2f\x0a\xaf" \
"\x1e\xa1\xab\x20\x1f\x6a\xeb\x84\x6a\xb9\x32\x5f\xa0\x40\x87\x51\x7a\x6b\x2f\x7c\xdf\x57\x9a\xab\x0c\xaa\xe7\x7f\x42\xf5" \
"\xcf\xdf\x55\x66\x42\x3d\xf3\x7a\xe0\x2c\x5e\x26\xd4\x45\x12\x52\x1d\xb9\x0d\xcf\xc2\x9a\x7f\xa3\xd2\xad\xe9\x94\x10\x84" \
"\xe4\x14\x42\xd2\x16\xe9\x6d\xf5\xf7\x99\x8f\xa5\x16\xb3\x27\xbe\xa2\x93\xe2\x49\xf5\x69\x2b\x18\x8d\xfa\x1c\xca\x5b\xac" \
"\xde\xf8\xff\xf8\xdb\x00\x52\x9c\xf5\x2e\x04\x94\xea\x1d\xae\xc0\xd1\xac\xee\x42\x40\xcd\x93\xec\xa4\xc4\x00\x52\xd0\x37" \
"\x80\x14\x80\xd4\xeb\x20\x45\x80\xf2\xe7\xa7\x50\xb9\xf0\xb3\xc2\xea\x3f\x35\xdf\x2e\xc8\x86\x3d\x70\x03\x90\xc9\xca\xd4" \
"\xa8\x9e\xff\x11\x93\x1f\xd0\x46\xb5\xf6\x98\x0a\x7b\x56\xd1\x9b\x9a\xff\xeb\x9d\x85\xdc\xf0\x0b\x80\x15\xff\x3a\x48\x0c" \
"\xc8\x5e\xb4\x14\xc5\xa3\x6f\xc2\x0f\xd9\x43\x49\x2b\xae\x53\xd8\xf3\x07\xd1\xb3\xef\x38\x6d\x02\x33\x75\xd2\xc6\x9f\x55" \
"\xda\xac\x4e\x7e\x34\xd1\x28\x94\x1c\x31\x82\x52\x78\xfd\x68\x22\x38\x3c\x74\x7c\xb4\xd3\x13\xb3\x68\x1b\xe2\x6d\xdb\x8d" \
"\xc0\xfa\x4a\x32\x6d\xb1\x98\x6f\x65\x7a\xc6\x4e\x80\xcd\x1b\x10\x1b\xcc\x48\x23\xac\x61\xdd\xc7\x9f\x81\xb3\x72\xf5\x8c" \
"\x67\xec\xbf\x89\x01\xf1\xcc\x99\x55\x43\x70\x1f\xd9\x14\x6b\x12\xf6\xe0\x62\xf4\xec\x7f\x17\x6c\xee\xb5\xb1\xfc\x45\x4e" \
"\x99\x15\xab\x90\x5b\xbf\x55\xa4\x8a\x2c\xd3\x02\x88\x67\xcd\x6d\xde\x0e\x67\xf9\x8a\xc8\x13\x70\xd7\x6e\x14\x36\xaa\x22" \
"\x07\x9a\x76\xb0\xfa\xaf\x87\xb7\x63\x8c\x1e\x40\x7a\x4a\xd3\x13\x85\x4f\x8e\x9a\x6b\x85\x91\x71\x58\x73\xe7\x45\xaa\xad" \
"\x74\x6c\x0f\xca\x5f\x9c\x8e\xe4\x23\x33\x66\x59\x17\x85\xd1\xc3\xb5\x87\xb3\xcc\x26\xaa\x5c\x1f\x20\xca\xcc\xe6\xf4\xd5" \
"\xda\xb5\xbc\x85\xd9\xea\xf0\x2b\x53\x28\x8e\xef\x42\xf9\xb3\x0f\x5b\x75\x91\xda\xe5\xa9\xf9\x6f\xeb\xd8\xed\xd7\x65\xd0" \
"\x0a\x88\xc7\xb5\x97\xdd\x81\xfc\x93\x3b\xea\x52\xa8\x7f\xfa\x95\x0a\x8a\x87\x46\x51\xfe\xf4\xa4\xda\x58\x62\xe1\x0e\x3d" \
"\x8a\xec\xd0\x3a\x89\x36\xbe\xb8\x61\x6b\xcf\xc3\xe8\x6a\x77\x54\x2f\x5d\xf8\x77\xbd\x32\x93\x61\x7a\xd9\x52\x7a\x7b\x1f" \
"\xca\xe7\xce\x08\x67\xcc\x5f\xcd\xb3\x26\xbe\x94\x37\xb1\x68\x29\x51\xb9\x48\x71\x05\xc3\x1e\x5c\x14\xba\x44\x10\xb8\x08" \
"\x45\xc1\x76\x47\xe2\x75\x90\x30\x0b\x09\xad\x81\x05\x42\x15\x0b\xe9\xf5\xf8\xd5\x2a\x50\xa1\xff\xb2\x41\xcd\x3b\x7b\xe1" \
"\x12\x99\x36\x15\xb9\xf6\x5b\x2c\xf1\x2c\x67\xae\xb8\xc4\x81\xf4\x04\xe8\x3e\x40\x7a\xea\xd2\x16\xc5\x00\x52\xa0\xec\x42" \
"\x40\xdd\x75\x8f\x75\x21\x20\xc5\x29\x6d\xb3\xda\x00\x52\x00\x6f\x3b\xa0\xcc\xea\x87\x12\xed\xfc\x15\xf5\x68\x57\xb7\x1f" \
"\xd0\x3d\x0f\xc0\x5d\x3b\xac\xbd\x90\xb4\x02\xb6\x1d\x10\x2f\x24\xb7\x85\x76\xfe\xb7\xdc\x99\x56\x4d\x5a\xe3\x76\x04\x10" \
"\x6c\x87\x3e\x56\xa2\x9d\x3f\x6d\x6e\xbb\x7d\x74\x06\x10\x51\x61\xd4\x16\xf1\x5e\xa1\x6f\x90\x2c\x3b\xc0\x28\xac\xd7\x1c" \
"\x30\x6d\xc3\x61\xc7\x00\xf1\xda\x6a\xdf\x20\x0d\x3f\xdf\x86\x32\xe3\xa7\xe8\x28\x20\x3e\x6d\xf7\xb1\x27\x90\xb9\xfb\xfe" \
"\xf8\x15\xa4\xec\xd9\x71\x40\x74\xb3\xc1\x7b\x71\x2f\xec\xeb\x06\x53\x2e\x35\x5e\xf8\x2e\x00\x44\x88\xe8\x63\x26\x8f\xbe" \
"\x41\x62\x6e\x2e\x5e\x15\x29\x7a\x35\x6d\x7c\x74\x35\xcc\xe2\xcc\x99\x77\x14\x33\xb4\x4e\xe2\x1f\x6d\x75\x6a\x04\x1b\x66" \
"\x9d\x9a\x87\xc9\x6b\x08\x18\x02\x86\x80\x21\x60\x08\x24\x27\xf0\x0f\x3d\x09\xd3\xf6\xe7\x71\x0b\x3f\x00\x00\x00\x00\x49" \
"\x45\x4e\x44\xae\x42\x60\x82";

@interface BFSwitch : UISwitch
@property (retain) NSString *switchName;
@end

@implementation BFSwitch
@synthesize switchName;
-(id)init {
    return [super init];
}
@end

@implementation iSpyHoverButton

- (id)init {
    self = [super init];
    
    if(!self)
        return self;
    
    NSString *f = [NSString stringWithFormat:@"%@/bflogo2.png", [[iSpy sharedInstance] docPath]];
    FILE *fp = fopen([f UTF8String], "w");
    if(fp) {
        fwrite(BFLogoPNG, 1, 1237, fp);
        fclose(fp);
    }

    self.window = [[FloatingButtonWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = self;
    self.window.hidden = false;
    self.window.windowLevel = DBL_MAX; //UIWindowLevelAlert + 1;
    
    // If the keyboard is activated, it'll be above the button. Fix that.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidShow:) name:UIKeyboardDidShowNotification object: nil];

    return self;
}
    
-(IBAction)buttonPressed {
    NSLog(@"Button pressed!");
    
    // Solidify the BF button
    self.view.alpha = 1;
    
    // Build the popover view
    self.popControllerVC = [[UIViewController alloc] init];
    self.popControllerVC.modalPresentationStyle = UIModalPresentationPopover;
    self.popController = [self.popControllerVC popoverPresentationController];
    self.popController.delegate = self;
    self.popController.permittedArrowDirections = UIPopoverArrowDirectionUp;
    self.popController.sourceView = self.popControllerVC.view;
    self.window.popController = self.popController;
    
    // populate it with a tableview
    UITableViewController *tbl = [[UITableViewController alloc] initWithStyle:UITableViewStylePlain];
    [tbl.tableView setDelegate:self];
    [tbl.tableView setDataSource:self];
    [self.popControllerVC.view addSubview:tbl.view];

    // Put the popover in the correct position
    self.popController.sourceRect = CGRectMake(self.buttonBF.center.x - 60, self.buttonBF.center.y - 88, 100, 100);
    
    // show the popover
    [self presentViewController:self.popControllerVC animated:YES completion:nil];
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 4;
}

-(IBAction)switchChanged:(BFSwitch *)sender
{
    BOOL setting = sender.isOn;
    NSLog(@"Switch '%@' is now %s", sender.switchName, (setting)?"on":"off");

    if(strcmp([[sender switchName] UTF8String], "pinningCell") == 0) {
        [[[iSpy sharedInstance] SSLPinningBypass] setEnabled:(setting)?ISPY_ENABLED:ISPY_DISABLED];
        NSLog(@"Pinning is now %s!", (setting)?"on":"off");
    } 
    else 
    if(strcmp([[sender switchName] UTF8String], "cycriptCell") == 0) {
        NSLog(@"Cycript!");
        //[[[iSpy sharedInstance] SSLPinningBypass] setState:(setting)?ISPY_ENABLED:ISPY_DISABLED];
    }
    else
    if(strcmp([[sender switchName] UTF8String], "decryptCell") == 0) {
        NSLog(@"Decrypt!");
        //[[[iSpy sharedInstance] SSLPinningBypass] setState:(setting)?ISPY_ENABLED:ISPY_DISABLED];
    }
    else
    if(strcmp([[sender switchName] UTF8String], "APICell") == 0) {
        NSLog(@"API!");
        //[[[iSpy sharedInstance] SSLPinningBypass] setState:(setting)?ISPY_ENABLED:ISPY_DISABLED];
    }

}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath {
    NSArray *switches = @[
                          @{ @"identifier": @"cycriptCell", @"text": @"Enable Cycript", @"state": /*[[iSpy sharedInstance] cycriptState]*/@0 },
                          @{ @"identifier": @"pinningCell", @"text": @"Bypass SSL pinning", @"state": @1 },
                          @{ @"identifier": @"APICell", @"text": @"Enable iSpy API", @"state": @1 },
                          @{ @"identifier": @"decryptCell", @"text": @"Decrypt app", @"state": @0 }
                          ];
    
    unsigned long rowNumber = (unsigned long)[indexPath indexAtPosition:1];
    int tag = (int)rowNumber + 31337;
    NSLog(@"indexPath: %ld", rowNumber);
    
    NSDictionary *sw = [switches objectAtIndex:rowNumber];
    NSString *cellIdentifier = [sw objectForKey:@"identifier"];
    
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        BFSwitch* s = [[BFSwitch alloc] init];
        CGSize switchSize = [s sizeThatFits:CGSizeZero];
        s.frame = CGRectMake(cell.contentView.bounds.size.width - switchSize.width - 5.0f,
                             (cell.contentView.bounds.size.height - switchSize.height) / 2.0f,
                             switchSize.width,
                             switchSize.height);
        s.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        s.tag = tag;
        NSLog(@"sw on: %d",  [[sw objectForKey:@"state"] boolValue]);
        [s setSwitchName: cellIdentifier];
        [s addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:s];
        dispatch_async(dispatch_get_main_queue(), ^{
            [s setOn: [[sw objectForKey:@"state"] boolValue] animated:YES];
            
        });
        
        UILabel* l = [[UILabel alloc] init];
        l.text = [sw objectForKey:@"text"];
        CGRect labelFrame = CGRectInset(cell.contentView.bounds, 10.0f, 8.0f);
        labelFrame.size.width = cell.contentView.bounds.size.width / 2.0f;
        l.font = [UIFont boldSystemFontOfSize:17.0f];
        l.frame = labelFrame;
        l.backgroundColor = [UIColor clearColor];
        cell.accessibilityLabel = [sw objectForKey:@"text"];
        [cell.contentView addSubview:l];
    }
    ((UISwitch*)[cell.contentView viewWithTag:tag]).on = false; // "value" is whatever the switch should be set to
    return cell;
}

- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController *)popoverPresentationController {
        self.view.alpha = ALPHA_VALUE;
}

- (BOOL)popoverPresentationControllerShouldDismissPopover:(UIPopoverPresentationController *)popoverPresentationController {
    return YES;
}

-(void)loadView {
    NSLog(@"[iSpy] hoverbutton: loadView");
    // Make the BF button
    self.view = [[UIView alloc] init];
    [self setButtonBF: [UIButton buttonWithType:UIButtonTypeCustom]];
    self.window.button = self.buttonBF;
    NSString *f = [NSString stringWithFormat:@"%@/bflogo2.png", [[iSpy sharedInstance] docPath]];
    [[self buttonBF] setImage:[UIImage imageNamed:f] forState:UIControlStateNormal];
    [[self buttonBF] setImage:[UIImage imageNamed:f] forState:UIControlStateHighlighted];
    [[self buttonBF] setBackgroundColor:[UIColor whiteColor]];
    self.buttonBF.layer.cornerRadius = 5;
    self.buttonBF.clipsToBounds = YES;
    [[self buttonBF] sizeToFit];
    CGRect c;
    c.origin = CGPointMake(10, 10);
    c.size = self.buttonBF.bounds.size;
    [[self buttonBF] setFrame:c];
    [[self buttonBF] addTarget:self action:@selector(buttonPressed) forControlEvents:UIControlEventPrimaryActionTriggered];
    
    // Add button to UIView
    [self.view addSubview:self.buttonBF];
    
    // Make button slightly transparent
    self.view.alpha = ALPHA_VALUE;
    
    // Add a pan gesture so we can drag the button around the UI
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panDidFire:)];
    [pan setCancelsTouchesInView:true];
    [pan setDelaysTouchesBegan:true];
    [pan setDelaysTouchesEnded:true];
    
    // Add gesture to button
    [[self buttonBF] addGestureRecognizer:pan];
}
    
- (void)keyboardDidShow:(NSNotificationName)name {
    printf("keyboardDidShow, putting the BF widget back on top");
    self.window.windowLevel = 0;
    self.window.windowLevel = DBL_MAX;
}
    
- (void)viewDidLoad
{
    NSLog(@"[iSpy] hoverbutton: viewDidLoad");
    [super viewDidLoad];
    [self viewDidLayoutSubviews];
    printf("iSpyViewController loaded\n");
}
    
-(void)snapButtonToSocket {
    printf("FIX ME\n");
}
    
-(void)viewDidLayoutSubviews {
    NSLog(@"[iSpy] hoverbutton: viewDidLayoutSubviews");
    [super viewDidLayoutSubviews];
    [self snapButtonToSocket];
}
    
-(void)panDidFire:(UIPanGestureRecognizer *)sender
{
    CGPoint offset = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];
    CGPoint center = self.buttonBF.center;
    center.x += offset.x;
    center.y += offset.y;
    self.buttonBF.center = center;
    if([sender state] == UIGestureRecognizerStateEnded || [sender state] == UIGestureRecognizerStateCancelled) {
        printf("FIXME relocate some stuff\n");
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}
-(void) showPopover { //}(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
    
    });
}
    
@end
