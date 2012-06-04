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

@end
