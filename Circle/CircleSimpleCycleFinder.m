//
//  CircleSimpleCycleFinder.m
//  Circle
//
//  Created by Michael Ash on 6/3/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import "CircleSimpleCycleFinder.h"

#import "CircleIVarLayout.h"


#define DEBUG_LOG 0

#define LOG(...) do { if(DEBUG_LOG) NSLog(__VA_ARGS__); } while(0)


@interface _CircleObjectInfo : NSObject

@property CFMutableSetRef incomingReferences;
@property CFMutableSetRef referringObjects;

@end

@implementation _CircleObjectInfo

- (id)init
{
    if((self = [super init]))
    {
        _incomingReferences = CFSetCreateMutable(NULL, 0, NULL);
        _referringObjects = CFSetCreateMutable(NULL, 0, NULL);
    }
    return self;
}

- (void)dealloc
{
    CFRelease(_incomingReferences);
    CFRelease(_referringObjects);
}

@end

static CFDictionaryRef CopyInfosForReferents(id obj)
{
    CFMutableDictionaryRef searchedObjs = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    CFMutableArrayRef toSearchObjs = CFArrayCreateMutable(NULL, 0, NULL);
    
    CFArrayAppendValue(toSearchObjs, (__bridge void *)obj);
    
    CFIndex count;
    while((count = CFArrayGetCount(toSearchObjs)) > 0)
    {
        void **candidate = (void **)CFArrayGetValueAtIndex(toSearchObjs, count - 1);
        CFArrayRemoveValueAtIndex(toSearchObjs, count - 1);
        
        LOG(@"Scanning candidate %p, retain count %lu", candidate, CFGetRetainCount((CFTypeRef)candidate));
        
        EnumerateStrongReferences(candidate, ^(void **reference, void *target) {
            if(target)
            {
                _CircleObjectInfo *info = (__bridge _CircleObjectInfo *)CFDictionaryGetValue(searchedObjs, target);
                if(!info)
                {
                    info = [[_CircleObjectInfo alloc] init];
                    CFDictionarySetValue(searchedObjs, target, (__bridge void *)info);
                    CFArrayAppendValue(toSearchObjs, target);
                }
                
                CFSetAddValue([info incomingReferences], reference);
                CFSetAddValue([info referringObjects], candidate);
            }
        });
    }
    CFRelease(toSearchObjs);
    
    return searchedObjs;
}

struct CircleSearchResults CircleSimpleSearchCycle(id obj)
{
    CFDictionaryRef infos = CopyInfosForReferents(obj);
    
    _CircleObjectInfo *info = (__bridge _CircleObjectInfo *)CFDictionaryGetValue(infos, (__bridge void *)obj);
    
    // short circuit: if there's no info object for obj, then it's not part of any sort of cycle
    if(!info)
    {
        struct CircleSearchResults results;
        results.isUnclaimedCycle = NO;
        results.incomingReferences = CFSetCreate(NULL, NULL, 0, NULL);
        return results;
    }
    
    CFSetRef incomingReferences = [info incomingReferences];
    NSUInteger retainCount = CFGetRetainCount((__bridge CFTypeRef)obj);
    LOG(@"%@ retain count is %lu, scanned incoming references are %@", obj, retainCount, CFBridgingRelease(CFCopyDescription(incomingReferences)));
    
    CFMutableArrayRef toSearchObjs = CFArrayCreateMutable(NULL, 0, NULL);
    CFArrayAppendValue(toSearchObjs, (__bridge void*)obj);
    
    CFMutableSetRef didSearchObjs = CFSetCreateMutable(NULL, 0, NULL);
    
    BOOL foundExternallyRetained = NO;
    
    CFIndex count;
    while((count = CFArrayGetCount(toSearchObjs)) > 0)
    {
        void *cycleObj = (void *)CFArrayGetValueAtIndex(toSearchObjs, count - 1);
        CFArrayRemoveValueAtIndex(toSearchObjs, count - 1);
        CFSetAddValue(didSearchObjs, cycleObj);
        
        _CircleObjectInfo *info = (__bridge _CircleObjectInfo *)CFDictionaryGetValue(infos, cycleObj);
        CFSetRef referencesCF = [info incomingReferences];
        CFIndex referencesCount = CFSetGetCount(referencesCF);
        
        CFIndex retainCount = CFGetRetainCount(cycleObj);
        if(cycleObj == (__bridge void *)obj)
            retainCount -= 2;
        
        
        if(retainCount != referencesCount)
        {
            foundExternallyRetained = YES;
            break;
        }
        
        CFSetRef referringObjectsCF = [info referringObjects];
        CFIndex referringObjectsCount = CFSetGetCount(referringObjectsCF);
        const void* referringObjects[referringObjectsCount];
        CFSetGetValues(referringObjectsCF, referringObjects);
        
        for(unsigned i = 0; i < referringObjectsCount; i++)
        {
            const void *referrer = referringObjects[i];
            if(!CFSetContainsValue(didSearchObjs, referrer))
               CFArrayAppendValue(toSearchObjs, referrer);
        }
    }
    
    LOG(@"foundExternallyRetained is %d", foundExternallyRetained);
    
    struct CircleSearchResults results;
    results.isUnclaimedCycle = !foundExternallyRetained;
    results.incomingReferences = CFRetain(incomingReferences);
    
    CFRelease(infos);
    CFRelease(toSearchObjs);
    CFRelease(didSearchObjs);
    
    return results;
}

void CircleZeroReferences(CFSetRef references)
{
    NSUInteger incomingReferencesCount = CFSetGetCount(references);
    
    const void *locations[incomingReferencesCount];
    CFSetGetValues(references, locations);
    for(unsigned i = 0; i < incomingReferencesCount; i++)
    {
        void **reference = (void **)locations[i];
        void *target = *reference;
        LOG(@"Zeroing reference %p to %p", reference, target);
        *reference = NULL;
        CFRelease(target);
    }
}

@interface _CircleWeakRef : NSObject
@property (weak) id obj;
@end
@implementation _CircleWeakRef
@end

@implementation CircleSimpleCycleFinder {
    NSMutableArray *_weakRefs;
}

- (id)init
{
    if((self = [super init]))
    {
        _weakRefs = [NSMutableArray array];
    }
    return self;
}

- (void)addCandidate: (id)obj
{
    _CircleWeakRef *ref = [[_CircleWeakRef alloc] init];
    [ref setObj: obj];
    [_weakRefs addObject: ref];
}

- (void)collect
{
    NSMutableIndexSet *zeroedIndices;
    
    NSUInteger index = 0;
    for(_CircleWeakRef *ref in _weakRefs)
    {
        id obj;
        @autoreleasepool {
            obj = [ref obj];
        }
        if(obj)
        {
            struct CircleSearchResults results = CircleSimpleSearchCycle(obj);
            if(results.isUnclaimedCycle)
                CircleZeroReferences(results.incomingReferences);
            CFRelease(results.incomingReferences);
        }
        else
        {
            if(!zeroedIndices)
                zeroedIndices = [NSMutableIndexSet indexSet];
            [zeroedIndices addIndex: index];
        }
        index++;
    }
    
    if(zeroedIndices)
        [_weakRefs removeObjectsAtIndexes: zeroedIndices];
}

@end

