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


enum Classification
{
    ENUMERABLE,
    DICTIONARY,
    BLOCK,
    OTHER
};

static unsigned kNoStrongReferencesLayout[] = { 0 };

static CFMutableDictionaryRef gLayoutCache;
static CFMutableDictionaryRef gClassificationCache;


struct _block_byref_block;
@interface _CircleReleaseDetector : NSObject {
    // __block fakery
    void *forwarding;
    int flags;   //refcount;
    int size;
    void (*byref_keep)(struct _block_byref_block *dst, struct _block_byref_block *src);
    void (*byref_dispose)(struct _block_byref_block *);
    void *captured[16];
    
    // our own stuff here
    BOOL _didRelease;
}

+ (void *)make; // And just free() the result when done
static BOOL DidRelease(void *obj);

@end
@implementation _CircleReleaseDetector

static void byref_keep_nop(struct _block_byref_block *dst, struct _block_byref_block *src) {}
static void byref_dispose_nop(struct _block_byref_block *param) {}

+ (void)initialize {
    Method m = class_getInstanceMethod(self, @selector(release_toSwizzle));
    class_addMethod(self, sel_getUid("release"), method_getImplementation(m), method_getTypeEncoding(m));
}

+ (void *)make {
    void *memory = calloc(class_getInstanceSize(self), 1);
    __unsafe_unretained _CircleReleaseDetector *obj = (__bridge __unsafe_unretained id)memory;
    object_setClass(obj, self);
    obj->forwarding = memory;
    obj->byref_keep = byref_keep_nop;
    obj->byref_dispose = byref_dispose_nop;
    return memory;
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

static unsigned *CalculateClassStrongLayout(Class c)
{
    SEL destructorSEL = sel_getUid(".cxx_destruct");
    
    void (*Destruct)(void *, SEL) = (__typeof__(Destruct))class_getMethodImplementation(c, destructorSEL);
    void (*Forward)(void *, SEL) = (__typeof__(Forward))class_getMethodImplementation([NSObject class], @selector(doNotImplementThisItDoesNotExistReally));
    
    if(Destruct == Forward)
        return kNoStrongReferencesLayout;
    
    return CalculateStrongLayout((__bridge void *)c, class_getInstanceSize(c), ^(void *fakeObj) {
        Destruct(fakeObj, destructorSEL);
    });
}

static unsigned *GetClassStrongLayout(Class c)
{
    if(!gLayoutCache)
        gLayoutCache = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    
    unsigned *layout = (unsigned *)CFDictionaryGetValue(gLayoutCache, (__bridge void *)c);
    if(!layout)
    {
        layout = CalculateClassStrongLayout(c);
        CFDictionarySetValue(gLayoutCache, (__bridge void *)c, layout);
    }
    return layout;
}


static unsigned *GetBlockStrongLayout(void *block)
{
    struct Block *realBlock = block;
    if(!(realBlock->flags & BLOCK_HAS_COPY_DISPOSE))
        return kNoStrongReferencesLayout;
    
    if(realBlock->flags & BLOCK_IS_GLOBAL)
        return kNoStrongReferencesLayout;
    
    struct BlockDescriptor *descriptor = realBlock->descriptor;
    
    void (*dispose_helper)(void *src) = descriptor->rest[1];
    
    if(!gLayoutCache)
        gLayoutCache = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    
    unsigned *layout = (unsigned *)CFDictionaryGetValue(gLayoutCache, dispose_helper);
    if(!layout)
    {
        layout = CalculateStrongLayout(realBlock->isa, descriptor->size, ^(void *fakeObj) {
            dispose_helper(fakeObj);
        });
        CFDictionarySetValue(gLayoutCache, dispose_helper, layout);
    }
    return layout;
}

static enum Classification Classify(void *obj)
{
    if(!gClassificationCache)
        gClassificationCache = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    
    void *key = (__bridge void *)object_getClass((__bridge id)obj);
    
    const void *value;
    Boolean present = CFDictionaryGetValueIfPresent(gClassificationCache, key, &value);
    if(present)
        return (enum Classification)value;
    
    enum Classification classification = OTHER;
    if(IsBlock(obj))
        classification = BLOCK;
    else if([(__bridge id)obj isKindOfClass: [NSArray class]] || [(__bridge id)obj isKindOfClass: [NSSet class]])
        classification = ENUMERABLE;
    else if([(__bridge id)obj isKindOfClass: [NSDictionary class]])
        classification = DICTIONARY;
    
    CFDictionarySetValue(gClassificationCache, key, (const void *)classification);
    
    return classification;
}

void EnumerateStrongReferences(void *obj, void (^block)(void **reference, void *target))
{
    enum Classification classification = Classify(obj);
    if(classification == ENUMERABLE)
    {
        for(id target in (__bridge id)obj)
            block(NULL, (__bridge void *)target);
    }
    else if(classification == DICTIONARY)
    {
        [(__bridge NSDictionary *)obj enumerateKeysAndObjectsUsingBlock: ^(id key, id obj, BOOL *stop) {
            block(NULL, (__bridge void *)key);
            block(NULL, (__bridge void *)obj);
        }];
    }
    else
    {
        unsigned *layout;
        if(classification == BLOCK)
            layout = GetBlockStrongLayout(obj);
        else
            layout = GetClassStrongLayout(object_getClass((__bridge id)obj));
        
        void **objAsReferences = obj;
        for(int i = 0; layout[i]; i++)
        {
            void **reference = &objAsReferences[layout[i]];
            void *target = reference ? *reference : NULL;
            block(reference, target);
        }
    }
}
