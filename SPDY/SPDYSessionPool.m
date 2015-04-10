//
//  SPDYSessionPool.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "SPDYSession.h"
#import "SPDYSessionPool.h"

@implementation SPDYSessionPool
{
    NSMutableArray *_sessions;
}

- (id)init
{
    self = [super init];
    if (self) {
        _sessions = [[NSMutableArray alloc] init];
    }
    return self;
}

- (bool)contains:(SPDYSession *)session
{
    return [_sessions containsObject:session];
}

- (void)add:(SPDYSession *)session
{
    [_sessions addObject:session];
}

- (NSUInteger)count
{
    return _sessions.count;
}

- (NSUInteger)remove:(SPDYSession *)session
{
    [_sessions removeObject:session];
    return _sessions.count;
}

- (SPDYSession *)nextSession
{
    SPDYSession *session;

    if (_sessions.count == 0) {
        return nil;
    }

    session = _sessions[0];
    NSAssert(session.isOpen, @"Should never contain closed sessions.");

    // TODO: clean this up
    while (!session.isOpen) {
        if ([self remove:session] == 0) return nil;
        session = _sessions[0];
    }

    // Rotate
    if (_sessions.count > 1) {
        [_sessions removeObjectAtIndex:0];
        [_sessions addObject:session];
    }

    return session;
}

@end
