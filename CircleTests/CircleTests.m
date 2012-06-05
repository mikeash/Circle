//
//  CircleTests.m
//  CircleTests
//
//  Created by Michael Ash on 4/30/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import "CircleTests.h"

#import "CircleSimpleCycleFinder.h"


@interface Referrer : NSObject
@property (strong) id ptr1;
@property (strong) id ptr2;
@end
@implementation Referrer
@end

@interface ReferrerSubclass : Referrer
@property (strong) id ptr3;
@end
@implementation  ReferrerSubclass
@end

@implementation CircleTests

- (void)testEmptyCollector
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    [collector collect];
}

- (void)testSimpleCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    @autoreleasepool {
        Referrer *a = [[Referrer alloc] init];
        Referrer *b = [[Referrer alloc] init];
        [a setPtr1: b];
        [b setPtr1: a];
        weakObj = a;
        
        [collector addCandidate: a];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNil(weakObj, @"Collector didn't collect a cycle");
}

- (void)testSingleObjectCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    @autoreleasepool {
        Referrer *a = [[Referrer alloc] init];
        [a setPtr1: a];
        weakObj = a;
        
        [collector addCandidate: a];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNil(weakObj, @"Collector didn't collect a cycle");
}

- (void)testBlockCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    @autoreleasepool {
        Referrer *a = [[Referrer alloc] init];
        id b = [^{ NSLog(@"%p", a); } copy];
        [a setPtr1: b];
        weakObj = a;
        
        [collector addCandidate: a];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNil(weakObj, @"Collector didn't collect a cycle");
}

- (void)testComplexCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    @autoreleasepool {
        Referrer *a = [[Referrer alloc] init];
        Referrer *b = [[Referrer alloc] init];
        Referrer *c = [[Referrer alloc] init];
        [a setPtr1: b];
        [a setPtr2: c];
        [b setPtr1: a];
        [b setPtr2: c];
        [c setPtr1: a];
        [c setPtr2: b];
        weakObj = a;
        
        [collector addCandidate: a];
        [collector addCandidate: b];
        [collector addCandidate: c];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNil(weakObj, @"Collector didn't collect a cycle");
}

- (void)testReachableCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    id obj;
    @autoreleasepool {
        Referrer *a = [[Referrer alloc] init];
        Referrer *b = [[Referrer alloc] init];
        [a setPtr1: b];
        [b setPtr1: a];
        weakObj = a;
        obj = b;
        
        [collector addCandidate: a];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNotNil(weakObj, @"Collector collected a referenced cycle");
}

- (void)testNSObject
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    id obj = [[NSObject alloc] init];
    [collector addCandidate: obj];
    [collector collect];
    // no asserts, we just want to make sure it doesn't crash
}

- (void)testManyCollections
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    id (^Cycle)(unsigned) = ^(unsigned length) {
        Referrer *root = [[Referrer alloc] init];
        Referrer *current = root;
        for(unsigned i = 1; i < length; i++)
        {
            Referrer *new = [[Referrer alloc] init];
            [current setPtr1: new];
            current = new;
        }
        [current setPtr1: root];
        return root;
    };
    
    int COUNT = 20;
    
    __weak id weakObjs[COUNT];
    id objs[COUNT];
    @autoreleasepool {
        for(int i = 0; i < COUNT; i++)
        {
            objs[i] = Cycle((i + 2) * 2);
            weakObjs[i] = objs[i];
            [collector addCandidate: objs[i]];
        }
    }
    
    @autoreleasepool {
        for(int i = 0; i < COUNT; i++)
            STAssertNotNil(weakObjs[i], @"Weak pointer to cycle should not be nil before running the collector");
    }
    
    for(int i = 0; i < COUNT; i++)
    {
        @autoreleasepool {
            objs[i] = nil;
            [collector collect];
        }
    }
    
    for(int i = 0; i < COUNT; i++)
        STAssertNil(weakObjs[i], @"Collector failed to collect a cycle");
}

- (void)testArrayCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    @autoreleasepool {
        Referrer *a = [[Referrer alloc] init];
        NSArray *b = @[ a ];
        [a setPtr1: b];
        weakObj = a;
        
        [collector addCandidate: a];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNil(weakObj, @"Collector didn't collect a cycle");
}

- (void)testSetCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    @autoreleasepool {
        Referrer *a = [[Referrer alloc] init];
        NSSet *b = [NSSet setWithObject: a];
        [a setPtr1: b];
        weakObj = a;
        
        [collector addCandidate: a];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNil(weakObj, @"Collector didn't collect a cycle");
}

- (void)testDictionaryCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    @autoreleasepool {
        Referrer *a = [[Referrer alloc] init];
        NSDictionary *b = @{ @"a" : a };
        [a setPtr1: b];
        weakObj = a;
        
        [collector addCandidate: a];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNil(weakObj, @"Collector didn't collect a cycle");
}

- (void)test__blockReference
{
    __block id obj = self;
    id block = ^{ NSLog(@"%@", obj); };
    block = [block copy];
    
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    [collector addCandidate: block];
    [collector collect];
}

- (void)testSimpleSubclassCycle
{
    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];
    
    __weak id weakObj;
    @autoreleasepool {
        Referrer *a = [[ReferrerSubclass alloc] init];
        Referrer *b = [[ReferrerSubclass alloc] init];
        [a setPtr1: b];
        [b setPtr1: a];
        weakObj = a;
        
        [collector addCandidate: a];
    }
    
    @autoreleasepool {
        STAssertNotNil(weakObj, @"Weak pointer to cycle should not be nil before running the collector");
    }
    [collector collect];
    STAssertNil(weakObj, @"Collector didn't collect a cycle");
}

@end
