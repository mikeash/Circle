//
//  MAAppDelegate.m
//  Circle
//
//  Created by Michael Ash on 4/30/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import "MAAppDelegate.h"

#import <dlfcn.h>
#import <objc/runtime.h>

#import "CircleIVarLayout.h"
#import "CircleSimpleCycleFinder.h"


@interface TestClass : NSObject
@property (strong) id ptr;
@property (strong) id ptr2;
@end
@implementation TestClass

+ (void)initialize {
    Method m = class_getInstanceMethod(self, @selector(retain_toSwizzle));
    class_addMethod(self, sel_getUid("retain"), method_getImplementation(m), method_getTypeEncoding(m));
}

+ (void *)make {
    void *obj = calloc(class_getInstanceSize(self), 1);
    object_setClass((__bridge id)obj, self);
    return obj;
}

- (void)retain_toSwizzle {
    //NSLog(@"Retaining %p at %@", self, [NSThread callStackSymbols]);
    void (*retain)(id, SEL) = (__typeof__(retain))[[TestClass superclass] instanceMethodForSelector: sel_getUid("retain")];
    retain(self, sel_getUid("retain"));
}

- (void)dealloc
{
    NSLog(@"%@ deallocating", self);
}

@end

@implementation MAAppDelegate {
    id strong;
    __weak id weak;
    __unsafe_unretained id unsafe;
    int int1;
    id none;
    int int2;
    id array[10];
}

static void PrintLayout(unsigned *layout)
{
    NSMutableArray *strings = [NSMutableArray array];
    for(int i = 0; layout[i]; i++)
        [strings addObject: [NSString stringWithFormat: @"%u", layout[i]]];
    NSLog(@"Strong references at (%@)", [strings componentsJoinedByString: @", "]);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    unsigned *layout = CalculateClassStrongLayout([self class]);
    NSLog(@"MAAppDelegate");
    PrintLayout(GetStrongLayout((__bridge void *)self));
    
    __weak id weakSelf = self;
    void (^block)(void) = ^{
        NSLog(@"%@ %@ %p %@", self, aNotification, layout, weakSelf);
    };
    block = [block copy];
    layout = GetStrongLayout((__bridge void *)block);
    NSLog(@"Block");
    PrintLayout(layout);
    
    __weak id weakObj;
    @autoreleasepool {
        TestClass *a = [[TestClass alloc] init];
        TestClass *b = [[TestClass alloc] init];
        TestClass *c = [[TestClass alloc] init];
        [a setPtr: b];
        [a setPtr2: c];
        [b setPtr: a];
        [b setPtr2: self];
        [c setPtr: a];
        weakObj = a;
    }
    CircleSimpleSearchCycle(weakObj);
}

@end
