# Circle - a cycle collector for Objective-C ARC

Circle is a *highly experimental* cycle collector for Objective-C programs compiled with ARC. It is by no means complete, let alone production-ready. It is, however, really cool. Your contributions, should you choose to make any, would be most welcome.

## Quick Source Code Tour

Circle is divided into two parts. The first part is responsible for detecting the locations of strong references within an object, and is contained in `CircleIvarLayout`. It exposes the `EnumerateStrongReferences` function which is used by the collector to walk the object graph.

The second part is the cycle collector, and is located in `CircleSimpleCycleFinder`.

## API Use

Did you notice the part above where I mentioned this is incomplete and not production-ready? Because this code is totally incomplete and not production-ready.

That said, you can use it for some stuff. The first thing you want to do is create a collector:

    CircleSimpleCycleFinder *collector = [[CircleSimpleCycleFinder alloc] init];

Next, add some candidate objects to it. The collector does *not* search the entire object graph automatically. Rather, it searches the graph starting from candidate objects that you explicitly give to it.

    [collector addCandidate: myObj];
    [collector addCandidate: otherObj];

Next, you can run a collection cycle:

    [collector collect];

This will search for leaked object cycles involving the candidates and break them by zeroing out the strong references located within the candidate objects.

It's also possible to have the collector walk the graph and gather info about it without actually performing any collection:

    NSArray *infoArrays = [collector objectInfos];

The result is an array of arrays containing instances of `CircleObjectInfo`:

    for(NSArray *infos in infoArrays)
        for(CircleObjectInfo *info in infos)
            if([info leaked])
                NSLog(@"Found a leaked object: %@", [info object]);

The `CircleObjectInfo` class contains various information about each object that was traversed, including its address, whether it is externally referenced (has retains that can't be accounted for by the traversed cycle), whether it's part of a cycle at all, whether it's leaked (no object in the cycle is externally referenced), the objects within the cycle that refer to this object, and the locations of their strong references.

## License

Circle is made available under a BSD license. See the `LICENSE` file for the actual license text.
