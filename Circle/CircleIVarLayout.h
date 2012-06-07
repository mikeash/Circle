//
//  CircleIVarLayout.h
//  Circle
//
//  Created by Michael Ash on 6/1/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import <Foundation/Foundation.h>


// Enumerate the strong references in a given object, calling the block for each one found.
// The block's reference parameter may be NULL, in cases where the location of the strong
// reference cannot be determined (for example, when providing references pulled from
// Cocoa collections.
void EnumerateStrongReferences(void *obj, void (^block)(void **reference, void *target));
