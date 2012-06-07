//
//  CircleIVarLayout.m
//  Circle
//
//  Created by Michael Ash on 6/1/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import "CircleIVarLayout.h"

#import <objc/runtime.h>


// Blocks runtime structures and constants
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


// In order to know how to scan an object, the code needs to know what kind of object it is.
// Most objects (OTHER) get scanned by invoking the ARC destructor. Blocks are scanned by
// invoking the block destructor. Cocoa collections are scanned by enumerating them.
enum Classification
{
    ENUMERABLE,
    DICTIONARY,
    BLOCK,
    OTHER
};


// Dictionarys to cache the layout and classification of a class.
static CFMutableDictionaryRef gLayoutCache;
static CFMutableDictionaryRef gClassificationCache;


// This class detects releases sent to it and makes that information available to
// the outside. It's used to detect strong references by watching which ivar slots
// are released by the ARC/block destructor. It also makes a weak attempt to imitate
// a block byref structure to keep block destructors from crashing on byref slots.
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

// We deal in void * here because we can't let ARC do any sort of memory management.
+ (void *)make; // And just free() the result when done
static BOOL DidRelease(void *obj);

@end
@implementation _CircleReleaseDetector

static void byref_keep_nop(struct _block_byref_block *dst, struct _block_byref_block *src) {}
static void byref_dispose_nop(struct _block_byref_block *param) {}

+ (void)initialize {
    // Swizzle out -release, since ARC doesn't let us override it directly.
    Method m = class_getInstanceMethod(self, @selector(release_toSwizzle));
    class_addMethod(self, sel_getUid("release"), method_getImplementation(m), method_getTypeEncoding(m));
}

+ (void *)make {
    // Allocate memory manually to ensure ARC doesn't cause any trouble.
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

// Determine whether a given object is a block.
static BOOL IsBlock(void *obj)
{
    // Create a known block, then find the topmost superclass that isn't NSObject.
    // We assume that this topmost class is the topmost block class.
    Class blockClass = [[^{ NSLog(@"%p", obj); } copy] class];
    while(class_getSuperclass(blockClass) && class_getSuperclass(blockClass) != [NSObject class])
        blockClass = class_getSuperclass(blockClass);
    
    // If the object is an instance of the block class, then it's a block. Otherwise not.
    Class candidate = object_getClass((__bridge id)obj);
    return [candidate isSubclassOfClass: blockClass];
}

// Calculate the layout of strong ivars for an object with a given isa, class, and destructor.
static NSIndexSet *CalculateStrongLayout(void *isa, size_t objSize, void(^destruct)(void *fakeObj))
{
    // We need to know how big pointers are so we can figure out how much memory to allocate.
    // We can pretty safely assume that pointer ivars are aligned, but we don't know which
    // ivars are pointers and which aren't. If somehow the object size is not a multiple
    // of the pointer size, we'll round up, so every slot can be filled.
    size_t ptrSize = sizeof(void *);
    
    // Figure out the number of pointers it takes to fill out the object.
    size_t elements = (objSize + ptrSize - 1) / ptrSize;
    
    // Create a fake object of the appropriate length.
    void *obj[elements];
    
    // Also create a separate array to track the release detectors so we can check on them after.
    // We can't query the contents of 'obj' because the destructor may zero out ivars.
    void *detectors[elements];
    
    // Set up the object. The first slot is the isa, the rest are release detectors.
    obj[0] = isa;
    for (size_t i = 0; i < elements; i++)
        detectors[i] = obj[i] = [_CircleReleaseDetector make];
    
    // Invoke the destructor.
    destruct(obj);
    
    // Run through the release detectors and add each one that got released to the object's
    // strong ivar layout. While we're at it, free the release detectors.
    NSMutableIndexSet *layout = [NSMutableIndexSet indexSet];

    for (unsigned i = 0; i < elements; i++) {
        if(DidRelease(detectors[i]))
            [layout addIndex: i];
        free(detectors[i]);
    }
    
    return layout;
}

static NSIndexSet *GetClassStrongLayout(Class c);

// Calculate the strong ivar layout for a given class.
static NSIndexSet *CalculateClassStrongLayout(Class c)
{
    // Fetch the selector for the ARC destructor.
    SEL destructorSEL = sel_getUid(".cxx_destruct");
    
    // Fetch the IMP for the destructor. Also fetch the IMP for a known unimplemented selector.
    void (*Destruct)(void *, SEL) = (__typeof__(Destruct))class_getMethodImplementation(c, destructorSEL);
    void (*Forward)(void *, SEL) = (__typeof__(Forward))class_getMethodImplementation([NSObject class], @selector(doNotImplementThisItDoesNotExistReally));
    
    // If the ARC destructor is not implemented (IMP equals that of an unimplemented selector)
    // then the class contains no strong references. We can just bail out now.
    if(Destruct == Forward)
        return [NSIndexSet indexSet];
    
    // Calculate the strong layout for an object with this class as isa, the appropriate size,
    // and a destructor that calls the ARC destructor IMP.
    NSIndexSet *layout = CalculateStrongLayout((__bridge void *)c, class_getInstanceSize(c), ^(void *fakeObj) {
        Destruct(fakeObj, destructorSEL);
    });
    
    // The ARC destructor does not call super. We have to mix in super ivars manually.
    Class superclass = [c superclass];
    if(superclass)
    {
        // Get the strong layout for the superclass, and add its layout to the current one.
        NSIndexSet *superLayout = GetClassStrongLayout(superclass);
        NSMutableIndexSet *both = [layout mutableCopy];
        [both addIndexes: superLayout];
        layout = both;
    }
    return layout;
}

// Fetch the strong ivar layout for a class, pulling from the cache when possible.
static NSIndexSet *GetClassStrongLayout(Class c)
{
    // If the layout cache doesn't exist, create it now. We'll be adding an entry.
    if(!gLayoutCache)
        gLayoutCache = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    
    // Fetch the layout from the cache.
    NSIndexSet *layout = (__bridge NSIndexSet *)CFDictionaryGetValue(gLayoutCache, (__bridge void *)c);
    
    // If the layout doesn't exist in the cache, then compute it and cache it.
    if(!layout)
    {
        layout = CalculateClassStrongLayout(c);
        CFDictionarySetValue(gLayoutCache, (__bridge void *)c, (__bridge void *)layout);
    }
    
    return layout;
}

// Fetch the strong reference layout for a block, pulling from the cache when possible.
static NSIndexSet *GetBlockStrongLayout(void *block)
{
    // We know it's a block here, so we can use the Block structure to access things.
    struct Block *realBlock = block;
    
    // If the block doesn't have a destructor then it has no strong references.
    if(!(realBlock->flags & BLOCK_HAS_COPY_DISPOSE))
        return [NSIndexSet indexSet];
    
    // Global blocks likewise have no strong references.
    if(realBlock->flags & BLOCK_IS_GLOBAL)
        return [NSIndexSet indexSet];
    
    // Otherwise, fetch the block destructor from the block's descriptor.
    struct BlockDescriptor *descriptor = realBlock->descriptor;
    
    void (*dispose_helper)(void *src) = descriptor->rest[1];
    
    // If the layout cache doesn't exist, create it now. We'll add an entry to it.
    if(!gLayoutCache)
        gLayoutCache = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    
    // See if the layout already exists. We can't use the block isa as a key, since different
    // blocks can share an isa. Instead, we use the address of the destructor function as the
    // key, since that destructor will always result in the same layout.
    NSIndexSet *layout = (__bridge NSIndexSet *)CFDictionaryGetValue(gLayoutCache, dispose_helper);
    
    // If the layout doesn't exist in the cache, calculate it using this block's isa, the block's
    // size as pulled from its descriptor, and a destructor that just calls the block destructor.
    if(!layout)
    {
        layout = CalculateStrongLayout(realBlock->isa, descriptor->size, ^(void *fakeObj) {
            dispose_helper(fakeObj);
        });
        CFDictionarySetValue(gLayoutCache, dispose_helper, (__bridge void *)layout);
    }
    
    return layout;
}

// Classify an object into one of the listed classifications.
static enum Classification Classify(void *obj)
{
    // If the classification cache doesn't exist, create it.
    if(!gClassificationCache)
        gClassificationCache = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    
    // Key classifications off the object's class.
    void *key = (__bridge void *)object_getClass((__bridge id)obj);
    
    // See if an entry exists in the cache, and return it if it does.
    const void *value;
    Boolean present = CFDictionaryGetValueIfPresent(gClassificationCache, key, &value);
    if(present)
        return (enum Classification)value;
    
    // Objects are OTHER unless otherwise determined.
    enum Classification classification = OTHER;
    
    // Blocks are, well, BLOCK.
    if(IsBlock(obj))
        classification = BLOCK;
    
    // Arrays and sets are ENUMERABLE. Other NSFastEnumeration classes can be added to this.
    else if([(__bridge id)obj isKindOfClass: [NSArray class]] || [(__bridge id)obj isKindOfClass: [NSSet class]])
        classification = ENUMERABLE;
    
    // Dictionaries are handled separately, since we have to enumerate keys and objects both.
    else if([(__bridge id)obj isKindOfClass: [NSDictionary class]])
        classification = DICTIONARY;
    
    // Set the computed classification in the cache, then return it.
    CFDictionarySetValue(gClassificationCache, key, (const void *)classification);
    
    return classification;
}

void EnumerateStrongReferences(void *obj, void (^block)(void **reference, void *target))
{
    // How we enumerate strong references depensd on the object's classification.
    enum Classification classification = Classify(obj);
    if(classification == ENUMERABLE)
    {
        // ENUMERABLE objects just use NSFastEnumeration.
        for(id target in (__bridge id)obj)
            block(NULL, (__bridge void *)target);
    }
    else if(classification == DICTIONARY)
    {
        // Dictionaries use the dictionary block enumeration to hit both keys and objects.
        [(__bridge NSDictionary *)obj enumerateKeysAndObjectsUsingBlock: ^(id key, id obj, BOOL *stop) {
            block(NULL, (__bridge void *)key);
            block(NULL, (__bridge void *)obj);
        }];
    }
    else
    {
        // Both BLOCK and OTHER use strong ivar layout data, although we have to fetch that layout
        // differently depending on the classification.
        NSIndexSet *layout;
        if(classification == BLOCK)
            layout = GetBlockStrongLayout(obj);
        else
            layout = GetClassStrongLayout(object_getClass((__bridge id)obj));
        
        // Treat the object as an array of void * to extract the references
        void **objAsReferences = obj;
        [layout enumerateIndexesUsingBlock: ^(NSUInteger idx, BOOL *stop) {
            // The reference is pointer #idx in the object.
            void **reference = &objAsReferences[idx];
            
            // The target is just what's located at the reference.
            // NOTE: I'm pretty sure this ?: is pointless here, and is held
            // over from when this code lived elsewhere. Need to verify before removing.
            void *target = reference ? *reference : NULL;
            block(reference, target);
        }];
    }
}
