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
};

struct CircleSearchResults CircleSimpleSearchCycle(id obj);
void CircleZeroReferences(CFSetRef references);
