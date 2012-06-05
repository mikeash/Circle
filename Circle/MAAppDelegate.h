//
//  MAAppDelegate.h
//  Circle
//
//  Created by Michael Ash on 4/30/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MAAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTableView *tableView;

- (IBAction)makeCycle:(id)sender;
- (IBAction)leakCycle:(id)sender;
- (IBAction)makeNonCycle:(id)sender;
- (IBAction)collect:(id)sender;

@end
