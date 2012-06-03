//
//  CircleSimpleCycleFinder.m
//  Circle
//
//  Created by Michael Ash on 6/3/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import "CircleSimpleCycleFinder.h"

#import "CircleIVarLayout.h"


@interface _CircleObjectInfo : NSObject

@property CFMutableArrayRef incomingReferences;

@end

@implementation _CircleObjectInfo

- (id)init
{
    if((self = [super init]))
    {
        _incomingReferences = CFArrayCreateMutable(NULL, 0, NULL);
    }
    return self;
}

- (void)dealloc
{
    CFRelease(_incomingReferences);
}

@end

static void ZeroIncomingReference(const void *value, void *context)
{
    void **reference = (void **)value;
    void *target = *reference;
    NSLog(@"Zeroing reference %p to %p", reference, target);
    *reference = NULL;
    CFRelease(target);
}

void CircleSimpleSearchCycle(id obj)
{
    CFMutableDictionaryRef searchedObjs = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    CFMutableArrayRef toSearchObjs = CFArrayCreateMutable(NULL, 0, NULL);
    
    CFArrayAppendValue(toSearchObjs, (__bridge void *)obj);
    
    CFIndex count;
    while((count = CFArrayGetCount(toSearchObjs)) > 0)
    {
        void **candidate = (void **)CFArrayGetValueAtIndex(toSearchObjs, count - 1);
        CFArrayRemoveValueAtIndex(toSearchObjs, count - 1);
        
        NSLog(@"Scanning candidate %p, retain count %lu", candidate, CFGetRetainCount((CFTypeRef)candidate));
        
        unsigned *layout = GetStrongLayout(candidate);
        for(int i = 0; layout[i]; i++)
        {
            void **reference = &candidate[layout[i]];
            void *target = *reference;
            if(target)
            {
                _CircleObjectInfo *info = (__bridge _CircleObjectInfo *)CFDictionaryGetValue(searchedObjs, target);
                if(!info)
                {
                    info = [[_CircleObjectInfo alloc] init];
                    CFDictionarySetValue(searchedObjs, target, (__bridge void *)info);
                    CFArrayAppendValue(toSearchObjs, target);
                }
                
                CFArrayAppendValue([info incomingReferences], reference);
            }
        }
    }
    
    _CircleObjectInfo *info = (__bridge _CircleObjectInfo *)CFDictionaryGetValue(searchedObjs, (__bridge void *)obj);
    CFMutableArrayRef incomingReferences = [info incomingReferences];
    NSUInteger retainCount = CFGetRetainCount((__bridge CFTypeRef)obj);
    NSLog(@"%@ retain count is %lu, scanned incoming references are %@", obj, retainCount, CFBridgingRelease(CFCopyDescription(incomingReferences)));
    
    NSUInteger incomingReferencesCount = CFArrayGetCount(incomingReferences);
    if(retainCount == incomingReferencesCount + 2)
    {
        NSLog(@"Accounted for all strong references to %@, breaking the cycle", obj);
        CFArrayApplyFunction(incomingReferences, CFRangeMake(0, incomingReferencesCount), ZeroIncomingReference, NULL);
    }
}
