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

static void PrintLayout(id obj)
{
    unsigned *layout = GetStrongLayout((__bridge void *)obj);
    NSMutableArray *strings = [NSMutableArray array];
    for(int i = 0; layout[i]; i++)
        [strings addObject: [NSString stringWithFormat: @"%u", layout[i]]];
    NSLog(@"%@: strong references located at offsets (%@)", obj, [strings componentsJoinedByString: @", "]);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    PrintLayout(self);
    
    __weak id weakSelf = self;
    void (^block)(void) = ^{
        NSLog(@"%@ %@ %@", self, aNotification, weakSelf);
    };
    block = [block copy];
    PrintLayout(block);
    
    __weak id weakObj1;
    __weak id weakObj2;
    __weak id weakObj3;
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    @autoreleasepool {
        TestClass *a = [[TestClass alloc] init];
        TestClass *b = [[TestClass alloc] init];
        TestClass *c = [[TestClass alloc] init];
        [a setPtr: b];
        [a setPtr2: c];
        [b setPtr: a];
        [b setPtr2: self];
        [c setPtr: a];
        weakObj1 = a;
        [collector addCandidate: a];
    }
    @autoreleasepool {
        TestClass *a = [[TestClass alloc] init];
        TestClass *b = [[TestClass alloc] init];
        TestClass *c = [[TestClass alloc] init];
        [a setPtr: b];
        [a setPtr2: c];
        [b setPtr: a];
        [b setPtr2: self];
        [c setPtr: a];
        weakObj2 = a;
        
        self->strong = b;
        NSLog(@"Before collecting, chaining gives %@", [self->strong ptr]);
        
        [collector addCandidate: a];
    }
    @autoreleasepool {
        TestClass *a = [[TestClass alloc] init];
        [a setPtr: [^{ NSLog(@"%@", a); } copy]];
        weakObj3 = a;
        [collector addCandidate: a];
    }
    @autoreleasepool {
        [collector collect];
    }
    NSLog(@"After collecting, weak objects are %@ %@ %@", weakObj1, weakObj2, weakObj3);
    NSLog(@"After collecting, chaining gives %@", [self->strong ptr]);
}

@end
