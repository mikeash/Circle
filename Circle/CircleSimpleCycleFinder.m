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


@implementation CircleObjectInfo

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

static void AddAddressString(const void *value, void *context)
{
    NSMutableArray *array = (__bridge id)context;
    [array addObject: [NSString stringWithFormat: @"%p", value]];
}

- (NSString *)description
{
    NSMutableArray *incomingReferencesStrings = [NSMutableArray array];
    CFSetApplyFunction(_incomingReferences, AddAddressString, (__bridge void *)incomingReferencesStrings);
    
    NSMutableArray *referringObjectsStrings = [NSMutableArray array];
    CFSetApplyFunction(_referringObjects, AddAddressString, (__bridge void *)referringObjectsStrings);
    
    return [NSString stringWithFormat: @"<%@: object=%p externallyReferenced:%s partOfCycle:%s incomingReferences=(%@) referringObjects=(%@)>",
            [self class],
            _object,
            _externallyReferenced ? "YES" : "NO",
            _partOfCycle ? "YES" : "NO",
            [incomingReferencesStrings componentsJoinedByString: @", "],
            [referringObjectsStrings componentsJoinedByString: @", "]];
}

@end

static CFMutableDictionaryRef CopyInfosForReferents(id obj)
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
                CircleObjectInfo *info = (__bridge CircleObjectInfo *)CFDictionaryGetValue(searchedObjs, target);
                if(!info)
                {
                    info = [[CircleObjectInfo alloc] init];
                    [info setObject: target];
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

struct CircleSearchResults CircleSimpleSearchCycle(id obj, BOOL gatherAll)
{
    CFMutableDictionaryRef infos = CopyInfosForReferents(obj);
    
    CircleObjectInfo *info = (__bridge CircleObjectInfo *)CFDictionaryGetValue(infos, (__bridge void *)obj);
    
    if(!info)
    {
        if(!gatherAll)
        {
            // short circuit: if there's no info object for obj, then it's not part of any sort of cycle
            struct CircleSearchResults results;
            results.isUnclaimedCycle = NO;
            results.referencesToZero = CFSetCreate(NULL, NULL, 0, NULL);
            results.infos = infos;
            return results;
        }
        else
        {
            // add an empty info for obj so the caller gets complete results
            info = [[CircleObjectInfo alloc] init];
            [info setObject: (__bridge void *)obj];
            CFDictionarySetValue(infos, (__bridge void *)obj, (__bridge void *)info);
        }
    }
    
    CFSetRef incomingReferences = [info incomingReferences];
    NSUInteger retainCount = CFGetRetainCount((__bridge CFTypeRef)obj);
    LOG(@"%@ retain count is %lu, scanned incoming references are %@", obj, retainCount, CFBridgingRelease(CFCopyDescription(incomingReferences)));
    
    CFMutableArrayRef toSearchObjs = CFArrayCreateMutable(NULL, 0, NULL);
    CFArrayAppendValue(toSearchObjs, (__bridge void*)obj);
    
    CFMutableSetRef didSearchObjs = CFSetCreateMutable(NULL, 0, NULL);
    
    BOOL foundExternallyRetained = NO;
    
    BOOL hasCycle = CFSetGetCount(incomingReferences) > 0;
    
    CFIndex count;
    while((count = CFArrayGetCount(toSearchObjs)) > 0)
    {
        void *cycleObj = (void *)CFArrayGetValueAtIndex(toSearchObjs, count - 1);
        CFArrayRemoveValueAtIndex(toSearchObjs, count - 1);
        CFSetAddValue(didSearchObjs, cycleObj);
        
        CircleObjectInfo *info = (__bridge CircleObjectInfo *)CFDictionaryGetValue(infos, cycleObj);
        CFSetRef referencesCF = [info incomingReferences];
        CFIndex referencesCount = CFSetGetCount(referencesCF);
        
        [info setPartOfCycle: hasCycle];
        
        CFIndex retainCount = CFGetRetainCount(cycleObj);
        if(cycleObj == (__bridge void *)obj)
            retainCount -= 2;
        
        if(retainCount != referencesCount)
        {
            foundExternallyRetained = YES;
            [info setExternallyReferenced: YES];
            if(!gatherAll)
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
    
    CFMutableSetRef referencesToZero = CFSetCreateMutable(NULL, 0, NULL);
    EnumerateStrongReferences((__bridge void *)obj, ^(void **reference, void *target) {
        if(target)
            CFSetAddValue(referencesToZero, reference);
    });
    
    struct CircleSearchResults results;
    results.isUnclaimedCycle = !foundExternallyRetained;
    results.referencesToZero = referencesToZero;
    results.infos = infos;
    
    CFRelease(toSearchObjs);
    CFRelease(didSearchObjs);
    
    return results;
}

void CircleZeroReferences(CFSetRef references)
{
    NSUInteger referencesCount = CFSetGetCount(references);
    
    const void *locations[referencesCount];
    CFSetGetValues(references, locations);
    for(unsigned i = 0; i < referencesCount; i++)
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

- (void)_enumerateObjectsGatherAll: (BOOL) gatherAll resultsCallback: (void (^)(struct CircleSearchResults results)) block
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
            struct CircleSearchResults results = CircleSimpleSearchCycle(obj, gatherAll);
            block(results);
            CFRelease(results.referencesToZero);
            CFRelease(results.infos);
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

- (void)collect
{
    [self _enumerateObjectsGatherAll: NO resultsCallback: ^(struct CircleSearchResults results) {
        if(results.isUnclaimedCycle)
            CircleZeroReferences(results.referencesToZero);
    }];
}

- (NSArray *)objectInfos
{
    NSMutableArray *infos = [NSMutableArray array];
    [self _enumerateObjectsGatherAll: YES resultsCallback: ^(struct CircleSearchResults results) {
        [infos addObject: [(__bridge id)results.infos allObjects]];
    }];
    return infos;
}

@end

