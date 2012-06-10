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
    CircleSimpleCycleFinder *_collector;
    NSArray *_infos;
    NSMutableArray *_retainedObjects;
}

- (id)init
{
    if((self = [super init]))
    {
        _collector = [[CircleSimpleCycleFinder alloc] init];
        _retainedObjects = [NSMutableArray array];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [NSTimer scheduledTimerWithTimeInterval: 0.1 target: self selector: @selector(_ping) userInfo: nil repeats: YES];
}

- (NSInteger)numberOfRowsInTableView: (NSTableView *)tableView
{
    return [_infos count];
}

- (id)tableView: (NSTableView *)tableView objectValueForTableColumn: (NSTableColumn *)tableColumn row: (NSInteger)row
{
    CircleObjectInfo *info = [_infos objectAtIndex: row];
    if(info == (id)[NSNull null])
        return @"";
    
    BOOL externallyReferenced = [info externallyReferenced];
    BOOL partOfCycle = [info partOfCycle];
    BOOL leaked = [info leaked];
    BOOL internallyReferenced = CFSetGetCount([info incomingReferences]) > 0;
    
    NSColor *color = (!partOfCycle ? [NSColor colorWithDeviceRed: 0.0 green: 0.5 blue: 0.0 alpha: 1.0] :
                      leaked ? [NSColor redColor] :
                      externallyReferenced && !internallyReferenced ? [NSColor blackColor] :
                      externallyReferenced && internallyReferenced ? [NSColor blueColor] :
                      !externallyReferenced && internallyReferenced ? [NSColor orangeColor] :
                      [NSColor greenColor]);
    
    NSAttributedString *str = [[NSAttributedString alloc] initWithString: [info description] attributes: @{ NSForegroundColorAttributeName : color }];
    
    return str;
}

- (void)_ping
{
    NSArray *infoArrays = [_collector objectInfos];
    NSMutableArray *array = [NSMutableArray array];
    for(NSArray *infos in infoArrays)
    {
        [array addObjectsFromArray: infos];
        [array addObject: [NSNull null]];
    }
    [array removeLastObject];
    _infos = array;
    [_tableView reloadData];
}

- (id)_makeObjects: (BOOL)cycle
{
    int count = random() % 4;
    TestClass *root = [[TestClass alloc] init];
    TestClass *current = root;
    for(int i = 0; i < count; i++)
    {
        TestClass *new = [[TestClass alloc] init];
        [current setPtr: new];
        if(random() % 2)
            [current setPtr2: [[TestClass alloc] init]];
        current = new;
    }
    
    if(cycle)
        [current setPtr: root];
    
    return root;
}

- (IBAction)makeCycle:(id)sender {
    id obj = [self _makeObjects: YES];
    [_retainedObjects addObject: obj];
    [_collector addCandidate: obj];
}

- (IBAction)leakCycle:(id)sender {
    id obj = [self _makeObjects: YES];
    [_collector addCandidate: obj];
}

- (IBAction)makeNonCycle:(id)sender {
    id obj = [self _makeObjects: NO];
    [_retainedObjects addObject: obj];
    [_collector addCandidate: obj];
}

- (IBAction)collect:(id)sender {
    [_collector collect];
}

@end
