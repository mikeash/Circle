//
//  CircleIVarLayout.h
//  Circle
//
//  Created by Michael Ash on 6/1/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import <Foundation/Foundation.h>


unsigned *CalculateClassStrongLayout(Class c);
unsigned *CalculateBlockStrongLayout(void *block);

unsigned *GetStrongLayout(void *obj);

void EnumerateStrongReferences(void *obj, void (^block)(void **reference, void *target));
