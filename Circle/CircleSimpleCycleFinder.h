//
//  CircleSimpleCycleFinder.h
//  Circle
//
//  Created by Michael Ash on 6/3/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import <Foundation/Foundation.h>


struct CircleSearchResults
{
    BOOL isUnclaimedCycle;
    CFSetRef incomingReferences;
    CFDictionaryRef infos;
};

struct CircleSearchResults CircleSimpleSearchCycle(id obj, BOOL gatherAll);
void CircleZeroReferences(CFSetRef references);

@interface CircleObjectInfo : NSObject

@property void *object;
@property BOOL externallyReferenced;
@property BOOL partOfCycle;
@property CFMutableSetRef incomingReferences;
@property CFMutableSetRef referringObjects;

@end

@interface CircleSimpleCycleFinder : NSObject

- (void)addCandidate: (id)obj;
- (void)collect;
- (NSArray *)objectInfos;

@end
