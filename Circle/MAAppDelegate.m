//
//  MAAppDelegate.m
//  Circle
//
//  Created by Michael Ash on 4/30/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import "MAAppDelegate.h"

#import <dlfcn.h>

#import "CircleIVarLayout.h"


@implementation MAAppDelegate {
    id strong;
    __weak id weak;
    __unsafe_unretained id unsafe;
    int int1;
    id none;
    int int2;
    id array[10];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    unsigned *layout = CalculateClassStrongLayout([self class]);
    NSMutableArray *strings = [NSMutableArray array];
    for(int i = 0; layout[i]; i++)
        [strings addObject: [NSString stringWithFormat: @"%u", layout[i]]];
    NSLog(@"Class %@ has strong references at (%@)", [self class], [strings componentsJoinedByString: @", "]);
}

@end
