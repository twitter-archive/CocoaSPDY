//
//  SPDYStreamManager.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>
#import "SPDYStreamManager.h"
#import "SPDYProtocol.h"
#import "SPDYStream.h"


@interface SPDYStreamNode : NSObject
@end

@implementation SPDYStreamNode
{
  @public
    __strong SPDYStreamNode *next;
    __strong SPDYStreamNode *prev;
    __strong SPDYStream *stream;
    __unsafe_unretained SPDYProtocol *protocol;
    SPDYStreamId streamId;
}
@end

@interface SPDYStreamManager ()
- (void)_removeListNode:(SPDYStreamNode *)node;
@end

@implementation SPDYStreamManager
{
    SPDYStreamNode *_priorityHead[8];
    SPDYStreamNode *_priorityLast[8];
    CFMutableDictionaryRef _nodesByStreamId;
    CFMutableDictionaryRef _nodesByProtocol;
    NSUInteger _localCount;
    NSUInteger _remoteCount;
    unsigned long _mutations;
}

Boolean SPDYStreamIdEqual(const void *key1, const void *key2) {
    return (SPDYStreamId)key1 == (SPDYStreamId)key2;
}

CFHashCode SPDYStreamIdHash(const void *key) {
    return (CFHashCode)((SPDYStreamId)key);
}

CFStringRef SPDYStreamIdCopyDescription(const void *key) {
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d"), (SPDYStreamId)key);
}

- (id)init
{
    NSAssert(sizeof(void *) <= sizeof(unsigned long), @"pointer width must be <= unsigned long width");
    NSAssert(sizeof(void *) >= sizeof(SPDYStreamId), @"pointer width must be >= SPDYStreamId width");

    self = [super init];
    if (self) {
        CFDictionaryKeyCallBacks SPDYStreamIdKeyCallbacks = {
            0, NULL, NULL,
            SPDYStreamIdCopyDescription,
            SPDYStreamIdEqual,
            SPDYStreamIdHash
        };
        _nodesByStreamId = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 100,
            &SPDYStreamIdKeyCallbacks,
            &kCFTypeDictionaryValueCallBacks
        );
        _nodesByProtocol = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 100,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks
        );
        _localCount = 0;
        _remoteCount = 0;
        _mutations = 0;
    }
    return self;
}

- (void)dealloc
{
    CFRelease(_nodesByStreamId);
    CFRelease(_nodesByProtocol);
}

- (NSUInteger)count
{
    return _localCount + _remoteCount;
}

- (id)objectAtIndexedSubscript:(NSUInteger)idx
{
    SPDYStreamNode *node = (id)CFDictionaryGetValue(_nodesByStreamId, (void *)idx);
    return node ? node->stream : nil;
}

- (id)objectForKeyedSubscript:(id)key
{
    SPDYStreamNode *node = (id)CFDictionaryGetValue(_nodesByProtocol, (__bridge CFTypeRef)key);
    return node ? node->stream : nil;
}

- (SPDYStream *)nextPriorityStream
{
    SPDYStreamNode *currentNode;
    for (int priority = 0; priority < 8 && currentNode == NULL; priority++) {
        currentNode = _priorityHead[priority];
    }

    if (currentNode) {
        return currentNode->stream;
    }

    return nil;
}

- (void)addStream:(SPDYStream *)stream
{
    SPDYStreamNode *node = [[SPDYStreamNode alloc] init];
    node->stream = stream;
    node->protocol = stream.protocol;
    node->streamId = stream.streamId;
    [self _addListNode:node];
}

- (void)setObject:(id)obj atIndexedSubscript:(NSUInteger)idx
{
    if (obj) {
        SPDYStreamNode *node = [[SPDYStreamNode alloc] init];
        SPDYStream *stream = obj;
        node->stream = stream;
        node->protocol = stream.protocol;
        node->streamId = (SPDYStreamId)idx;

        [self _addListNode:node];
    } else {
        [self removeStreamWithStreamId:(SPDYStreamId)idx];
    }
}

- (void)_addListNode:(SPDYStreamNode *)node
{
    // Update linked list
    uint8_t priority = node->stream.priority;
    if (_priorityHead[priority] == NULL) {
        _priorityHead[priority] = node;
        _priorityLast[priority] = node;
    } else {
        _priorityLast[priority]->next = node;
        node->prev = _priorityLast[priority];
        _priorityLast[priority] = node;
    }

    // Update hash maps
    NSAssert(node->streamId != 0 || node->protocol != nil, @"cannot insert unaddressable stream");
    NSAssert(CFDictionaryGetValue(_nodesByStreamId, (void *)(uintptr_t)node->streamId) == NULL, @"cannot insert stream with duplicate streamId");
    if (node->streamId) {
        CFDictionarySetValue(_nodesByStreamId, (void *)(uintptr_t)node->streamId, (__bridge CFTypeRef)node);
    }
    if (node->protocol) {
        CFDictionarySetValue(_nodesByProtocol, (__bridge CFTypeRef)node->protocol, (__bridge CFTypeRef)node);
    }

    // Update counts
    if (node->stream.local) {
        _localCount += 1;
    } else {
        _remoteCount += 1;
    }

    _mutations += 1;
}

- (void)removeStreamWithStreamId:(SPDYStreamId)streamId
{
    SPDYStreamNode *node = (id)CFDictionaryGetValue(_nodesByStreamId, (void *)(uintptr_t)streamId);
    if (node) [self _removeListNode:node];
}

- (void)removeStreamForProtocol:(SPDYProtocol *)protocol
{
    SPDYStreamNode *node = (id)CFDictionaryGetValue(_nodesByProtocol, (__bridge CFTypeRef)protocol);
    if (node) [self _removeListNode:node];
}

- (void)_removeListNode:(SPDYStreamNode *)node
{
    // Update linked list
    uint8_t priority = node->stream.priority;
    if (node->next != NULL) node->next->prev = node->prev;
    if (node->prev != NULL) node->prev->next = node->next;
    if (_priorityHead[priority] == node) _priorityHead[priority] = node->next;
    if (_priorityLast[priority] == node) _priorityLast[priority] = node->prev;

    // Update hash maps
    if (node->streamId) {
        CFDictionaryRemoveValue(_nodesByStreamId, (void *)(uintptr_t)node->streamId);
    }
    if (node->protocol) {
        CFDictionaryRemoveValue(_nodesByProtocol, (__bridge CFTypeRef)node->protocol);
    }

    // Update counts
    if (node->stream.local) {
        _localCount -= 1;
    } else {
        _remoteCount -= 1;
    }

    _mutations += 1;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len
{
    SPDYStreamNode *currentNode = (__bridge SPDYStreamNode *)((void *)state->extra[0]);
    unsigned long *priority = &(state->state);

    for (; *priority < 8 && currentNode == NULL; *priority += 1) {
        currentNode = _priorityHead[*priority];
    }

    if (currentNode == NULL) {
        return 0;
    }

    NSUInteger i;
    for (i = 0; i < len && currentNode != NULL; i++) {
        buffer[i] = currentNode->stream;
        currentNode = currentNode->next;
    }

    state->extra[0] = (unsigned long)currentNode;
    state->itemsPtr = buffer;
    state->mutationsPtr = &_mutations;
    return i;
}

- (void)removeAllStreams
{
    // Update linked list
    for (int i = 0; i < 8; i++) {
        _priorityHead[i] = NULL;
        _priorityLast[i] = NULL;
    }

    // Update hash maps
    CFDictionaryRemoveAllValues(_nodesByStreamId);
    CFDictionaryRemoveAllValues(_nodesByProtocol);

    // Update counts
    _localCount = 0;
    _remoteCount = 0;

    _mutations += 1;
}

@end
