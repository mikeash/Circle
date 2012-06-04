//
//  CircleIVarLayout.m
//  Circle
//
//  Created by Michael Ash on 6/1/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import "CircleIVarLayout.h"

#import <objc/runtime.h>


struct BlockDescriptor
{
    unsigned long reserved;
    unsigned long size;
    void *rest[1];
};

struct Block
{
    void *isa;
    int flags;
    int reserved;
    void *invoke;
    struct BlockDescriptor *descriptor;
};

enum {
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25),
    BLOCK_HAS_CTOR =          (1 << 26), // helpers have C++ code
    BLOCK_IS_GLOBAL =         (1 << 28),
    BLOCK_HAS_STRET =         (1 << 29), // IFF BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE =     (1 << 30), 
};


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

static BOOL IsBlock(void *obj)
{
    Class blockClass = [[^{ NSLog(@"%p", obj); } copy] class];
    while(class_getSuperclass(blockClass) && class_getSuperclass(blockClass) != [NSObject class])
        blockClass = class_getSuperclass(blockClass);
    
    Class candidate = object_getClass((__bridge id)obj);
    return [candidate isSubclassOfClass: blockClass];
}

static unsigned *CalculateStrongLayout(void *isa, size_t objSize, void(^destruct)(void *fakeObj))
{
    size_t ptrSize = sizeof(void *);
    size_t elements = (objSize + ptrSize - 1) / ptrSize;
    void *obj[elements];
    void *detectors[elements];
    obj[0] = isa;
    for (size_t i = 0; i < elements; i++)
        detectors[i] = obj[i] = [_CircleReleaseDetector make];
    
    destruct(obj);

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

unsigned *CalculateClassStrongLayout(Class c)
{
    SEL destructorSEL = sel_getUid(".cxx_destruct");
    
    void (*Destruct)(void *, SEL) = (__typeof__(Destruct))class_getMethodImplementation(c, destructorSEL);
    void (*Forward)(void *, SEL) = (__typeof__(Forward))class_getMethodImplementation([NSObject class], @selector(doNotImplementThisItDoesNotExistReally));
    
    if(Destruct == Forward)
        return calloc(sizeof(unsigned), 1);
    
    return CalculateStrongLayout((__bridge void *)c, class_getInstanceSize(c), ^(void *fakeObj) {
        Destruct(fakeObj, destructorSEL);
    });
}

unsigned *CalculateBlockStrongLayout(void *block)
{
    struct Block *realBlock = block;
    if(!(realBlock->flags & BLOCK_HAS_COPY_DISPOSE))
        return calloc(sizeof(unsigned), 1);
    
    if(realBlock->flags & BLOCK_IS_GLOBAL)
        return calloc(sizeof(unsigned), 1);
    
    struct BlockDescriptor *descriptor = realBlock->descriptor;
    
    void (*dispose_helper)(void *src) = descriptor->rest[1];
    
    return CalculateStrongLayout(realBlock->isa, descriptor->size, ^(void *fakeObj) {
        dispose_helper(fakeObj);
    });
}

unsigned *GetStrongLayout(void *obj)
{
    return IsBlock(obj) ? CalculateBlockStrongLayout(obj) : CalculateClassStrongLayout(object_getClass((__bridge id)obj));
}
