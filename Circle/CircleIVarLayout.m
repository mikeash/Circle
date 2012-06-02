//
//  CircleIVarLayout.m
//  Circle
//
//  Created by Michael Ash on 6/1/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import "CircleIVarLayout.h"

#import <objc/runtime.h>


@interface _CircleReleaseDetector : NSObject {
    BOOL _didRelease;
}

+ (void *)make; // And just free() the result when done
static BOOL DidRelease(void *obj);

@end
@implementation _CircleReleaseDetector

+ (void)initialize {
    Method m = class_getInstanceMethod(self, @selector(release_toSwizzle));
    class_addMethod(self, sel_getUid("release"), method_getImplementation(m), method_getTypeEncoding(m));
}

+ (void *)make {
    void *obj = calloc(class_getInstanceSize(self), 1);
    object_setClass((__bridge id)obj, self);
    return obj;
}

- (void)release_toSwizzle {
    _didRelease = YES;
}

static BOOL DidRelease(void *obj) {
    return ((__bridge __unsafe_unretained _CircleReleaseDetector *)obj)->_didRelease;
}

@end

unsigned *CalculateClassStrongLayout(Class c)
{
    SEL destructorSEL = sel_getUid(".cxx_destruct");
    
    size_t ptrSize = sizeof(void *);
    size_t elements = (class_getInstanceSize(c) + ptrSize - 1) / ptrSize;
    void *obj[elements];
    void *detectors[elements];
    obj[0] = (__bridge void *)c;
    for (size_t i = 0; i < elements; i++)
        detectors[i] = obj[i] = [_CircleReleaseDetector make];
    
    void (*Destruct)(void *, SEL) = (__typeof__(Destruct))class_getMethodImplementation(c, destructorSEL);
    Destruct(obj, destructorSEL);
    
    unsigned *layout = malloc(sizeof(unsigned) * elements);
    int cursor = 0;
    
    for (unsigned i = 0; i < elements; i++) {
        if(DidRelease(detectors[i]))
            layout[cursor++] = i;
        free(detectors[i]);
    }
    layout[cursor] = 0;
    
    return layout;
}
