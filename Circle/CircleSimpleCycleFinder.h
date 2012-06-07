//
//  CircleSimpleCycleFinder.h
//  Circle
//
//  Created by Michael Ash on 6/3/12.
//  Copyright (c) 2012 Michael Ash. All rights reserved.
//

#import <Foundation/Foundation.h>


// A structure used to return results from a cycle search.
// The CF objects are returned retained and must be released
// by the caller.
struct CircleSearchResults
{
    BOOL isUnclaimedCycle;
    CFSetRef referencesToZero;
    CFDictionaryRef infos;
};

// Search for a cycle starting from the given object. The object
// is assumed to have a retain count of 1 above what it would
// normally have (so the caller can have it retained after fetching
// it from a __weak variable).
// If gatherAll is false, then the search stops as soon as a cycle is
// known not to be possible and reduced info may be returned.
// If true, the full search is performed regardless, which is useful
// when you're after full object info.
struct CircleSearchResults CircleSimpleSearchCycle(id obj, BOOL gatherAll);

// Zero a set of references. This simply iterates the set and does
// CFRelease(*reference); *reference = NULL; for each item.
void CircleZeroReferences(CFSetRef references);

// Info from the collector about an object.
@interface CircleObjectInfo : NSObject

// The object pointer. Stored as a void * to allow greater control over retain/release
@property void *object;

// Whether the object is externally referenced. If NO, its retain count is exactly
// equal to what is caused by references within the cycle. If YES, some additional
// references are present.
@property BOOL externallyReferenced;

// Whether the object is part of the searched cycle, or just a leaf node.
@property BOOL partOfCycle;

// Whether the object has actualy been leaked. This is YES if all of the
// objects in the cycle have not been externally referenced.
@property BOOL leaked;

// The addresses of incoming references to this object that were found within the cycle.
// Conceptually the set stores id* values.
@property CFMutableSetRef incomingReferences;

// The addresses of referring objects within the cycle.
@property CFMutableSetRef referringObjects;

@end

// A very simple cycle finder.
@interface CircleSimpleCycleFinder : NSObject

// Add a candidate object to the collector. This collector only searches starting from
// candidate objects it is given. It does not search arbitrary objects.
- (void)addCandidate: (id)obj;

// Run a collection cycle. This searches all candidates, then breaks any leaked cycles
// it finds by zeroing out the strong references found within a candidate.
- (void)collect;

// Run the info-gathering portion of a collection cycle. The return value is an array
// of array of CircleObjectInfo instances. Each sub-array corresponds to a candidate.
// If a candidate refers to another candidate, directly or indirectly, duplicate object
// infos may appear in different sub-arrays, because this collector is neither particularly
// smart nor efficient.
- (NSArray *)objectInfos;

@end
