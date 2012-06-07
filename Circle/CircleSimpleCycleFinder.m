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

// Helper function used with CFSetApplyFunction.
static void AddAddressString(const void *value, void *context)
{
    NSMutableArray *array = (__bridge id)context;
    [array addObject: [NSString stringWithFormat: @"%p", value]];
}

- (NSString *)description
{
    // Map the sets of references and referring objects into strings.
    NSMutableArray *incomingReferencesStrings = [NSMutableArray array];
    CFSetApplyFunction(_incomingReferences, AddAddressString, (__bridge void *)incomingReferencesStrings);
    
    NSMutableArray *referringObjectsStrings = [NSMutableArray array];
    CFSetApplyFunction(_referringObjects, AddAddressString, (__bridge void *)referringObjectsStrings);
    
    return [NSString stringWithFormat: @"<%@: object=%p externallyReferenced:%s leaked:%s partOfCycle:%s incomingReferences=(%@) referringObjects=(%@)>",
            [self class],
            _object,
            _externallyReferenced ? "YES" : "NO",
            _leaked ? "YES" : "NO",
            _partOfCycle ? "YES" : "NO",
            [incomingReferencesStrings componentsJoinedByString: @", "],
            [referringObjectsStrings componentsJoinedByString: @", "]];
}

@end

// Scan all objects referenced by the given object, directly or indirectly, and generate
// CircleObjectInfo instances for them. Returns a dictionary mapping object addresses
// to info objects.
static CFMutableDictionaryRef CopyInfosForReferents(id obj)
{
    // Info instances go into this dictionary.
    CFMutableDictionaryRef searchedObjs = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    
    // An array of objects to search. This is used as a stack.
    CFMutableArrayRef toSearchObjs = CFArrayCreateMutable(NULL, 0, NULL);
    
    // Start out searching the given object.
    CFArrayAppendValue(toSearchObjs, (__bridge void *)obj);
    
    // Keep searching until the stack runs out of objects.
    CFIndex count;
    while((count = CFArrayGetCount(toSearchObjs)) > 0)
    {
        // Pop the object to search from the stack.
        void **candidate = (void **)CFArrayGetValueAtIndex(toSearchObjs, count - 1);
        CFArrayRemoveValueAtIndex(toSearchObjs, count - 1);
        
        LOG(@"Scanning candidate %p, retain count %lu", candidate, CFGetRetainCount((CFTypeRef)candidate));
        
        // Go through all of the strong references in the object.
        EnumerateStrongReferences(candidate, ^(void **reference, void *target) {
            // If the target is nil, there's nothing to do.
            if(target)
            {
                // Get the object's info object.
                CircleObjectInfo *info = (__bridge CircleObjectInfo *)CFDictionaryGetValue(searchedObjs, target);
                
                // If there is no info object make one. Also add this target to the stack
                // of objects to search, since we're the first one to get to it.
                if(!info)
                {
                    info = [[CircleObjectInfo alloc] init];
                    [info setObject: target];
                    CFDictionarySetValue(searchedObjs, target, (__bridge void *)info);
                    CFArrayAppendValue(toSearchObjs, target);
                }
                
                // Add the reference and object to the info object.
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
    // Fetch object infos for everything referenced by object.
    CFMutableDictionaryRef infos = CopyInfosForReferents(obj);
    
    // Fetch the object's info.
    CircleObjectInfo *info = (__bridge CircleObjectInfo *)CFDictionaryGetValue(infos, (__bridge void *)obj);
    
    if(!info)
    {
        // If there's no info object for obj, then it's not part of any sort of cycle. If we
        // aren't gathering all info, then we can just bail out now and return NO.
        if(!gatherAll)
        {
            struct CircleSearchResults results;
            results.isUnclaimedCycle = NO;
            results.referencesToZero = CFSetCreate(NULL, NULL, 0, NULL);
            results.infos = infos;
            return results;
        }
        else
        {
            // The caller still wants information. Add an empty info for obj, since the caller
            // is asking about it.
            info = [[CircleObjectInfo alloc] init];
            [info setObject: (__bridge void *)obj];
            CFDictionarySetValue(infos, (__bridge void *)obj, (__bridge void *)info);
        }
    }
    
    CFSetRef incomingReferences = [info incomingReferences];
    NSUInteger retainCount = CFGetRetainCount((__bridge CFTypeRef)obj);
    LOG(@"%@ retain count is %lu, scanned incoming references are %@", obj, retainCount, CFBridgingRelease(CFCopyDescription(incomingReferences)));
    
    // Create a stack of objects to search. Start the search with obj.
    CFMutableArrayRef toSearchObjs = CFArrayCreateMutable(NULL, 0, NULL);
    CFArrayAppendValue(toSearchObjs, (__bridge void*)obj);
    
    // Keep a list of objects we already searched, so we don't loop endlessly.
    CFMutableSetRef didSearchObjs = CFSetCreateMutable(NULL, 0, NULL);
    
    // Track whether we found any externally retained objects.
    BOOL foundExternallyRetained = NO;
    
    // Objects are part of a cycle if the object we're interested in has incoming references.
    // (Cycles among objects it points to that don't involve the top object don't count.)
    BOOL hasCycle = CFSetGetCount(incomingReferences) > 0;
    
    // Run through the object graph backwards, walking from each object to its referring objects.
    // This eliminates leaf nodes. If any of these objects are externally referenced, then the
    // cycle is not a leak.
    CFIndex count;
    while((count = CFArrayGetCount(toSearchObjs)) > 0)
    {
        // Pop the stack, and add the popped object to the set of searched objects.
        void *cycleObj = (void *)CFArrayGetValueAtIndex(toSearchObjs, count - 1);
        CFArrayRemoveValueAtIndex(toSearchObjs, count - 1);
        CFSetAddValue(didSearchObjs, cycleObj);
        
        // Fetch the object info for the object, its references, and how many references it has.
        CircleObjectInfo *info = (__bridge CircleObjectInfo *)CFDictionaryGetValue(infos, cycleObj);
        CFSetRef referencesCF = [info incomingReferences];
        CFIndex referencesCount = CFSetGetCount(referencesCF);
        
        [info setPartOfCycle: hasCycle];
        
        // An object is externally referenced if its retain count is not equal to the number
        // of strong references found within the cycle.
        CFIndex retainCount = CFGetRetainCount(cycleObj);
        
        // This is a naaaaaaasty hack. The object passed in to this function has its retain
        // count bumped twice. Once because it's retrieved from a weak reference, and a second
        // time because ARC retains function parameters. Compensate for that by subtracting 2
        // from its retain count.
        if(cycleObj == (__bridge void *)obj)
            retainCount -= 2;
        
        // See if the retain count matches the number of references.
        if(retainCount != referencesCount)
        {
            foundExternallyRetained = YES;
            [info setExternallyReferenced: YES];
            
            // If we weren't asked to gather all info, then we can just stop here.
            // This isn't a leaked cycle, since a member of the cycle is externally
            // referenced.
            if(!gatherAll)
                break;
        }
        
        // Walk through all referring objects and add them to the stack of objects to examine.
        CFSetRef referringObjectsCF = [info referringObjects];
        CFIndex referringObjectsCount = CFSetGetCount(referringObjectsCF);
        const void* referringObjects[referringObjectsCount];
        CFSetGetValues(referringObjectsCF, referringObjects);
        
        for(unsigned i = 0; i < referringObjectsCount; i++)
        {
            const void *referrer = referringObjects[i];
            
            // Make sure we don't search the same object twice.
            if(!CFSetContainsValue(didSearchObjs, referrer))
               CFArrayAppendValue(toSearchObjs, referrer);
        }
    }
    
    LOG(@"foundExternallyRetained is %d", foundExternallyRetained);
    
    // Set all infos to leaked if no externally retained object was found.
    if(!foundExternallyRetained)
    {
        for(CircleObjectInfo *info in [(__bridge id)infos objectEnumerator])
            [info setLeaked: YES];
    }
    
    // Create a set of references to zero to break the cycle. These are simply the strong
    // references held by the object. (In theory, the references of any object in the cycle
    // would work. In practice, we can't zero the references of all objects, e.g. arrays,
    // and it's a bit dangerous to zero an arbitrary object's references since it might
    // actually use them in dealloc or something.
    CFMutableSetRef referencesToZero = CFSetCreateMutable(NULL, 0, NULL);
    EnumerateStrongReferences((__bridge void *)obj, ^(void **reference, void *target) {
        if(target)
            CFSetAddValue(referencesToZero, reference);
    });
    
    // Create the results structure, release objects, and return.
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

// A simple weak reference wrapper making it easy to fill an array with weak references.
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
    // Candidates are stored as weak references so that the collector doesn't keep them
    // alive in the instances where they don't leak, and so that the collector doesn't
    // place additional retains on them which would confuse the cycle finder.
    _CircleWeakRef *ref = [[_CircleWeakRef alloc] init];
    [ref setObj: obj];
    [_weakRefs addObject: ref];
}

// Enumerate over all candidate objects, gathering cycle search results for each one.
- (void)_enumerateObjectsGatherAll: (BOOL) gatherAll resultsCallback: (void (^)(struct CircleSearchResults results)) block
{
    NSMutableIndexSet *zeroedIndices;
    
    NSUInteger index = 0;
    for(_CircleWeakRef *ref in _weakRefs)
    {
        // Fetch the real object in an autorelease pool to ensure that the only retain on
        // it is the one from obj.
        id obj;
        @autoreleasepool {
            obj = [ref obj];
        }
        if(obj)
        {
            // Do the cycle search, call the block, and free the results.
            struct CircleSearchResults results = CircleSimpleSearchCycle(obj, gatherAll);
            block(results);
            CFRelease(results.referencesToZero);
            CFRelease(results.infos);
        }
        else
        {
            // The weak reference is nil. Add it to the set of zeroed weak references
            // for cleanup.
            if(!zeroedIndices)
                zeroedIndices = [NSMutableIndexSet indexSet];
            [zeroedIndices addIndex: index];
        }
        index++;
    }
    
    // Remove all zeroed weak references from the array.
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

