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

#import "SPDYProtocol.h"
#import "SPDYSession.h"
#import "SPDYSessionManager.h"
#import "SPDYSessionPool.h"
#import "SPDYStream.h"

@implementation SPDYSessionPool
{
    NSMutableArray *_sessions;
}

- (id)initWithOrigin:(SPDYOrigin *)origin manager:(SPDYSessionManager *)manager cellular:(bool)cellular error:(NSError **)pError
{
    self = [super init];
    if (self) {
        SPDYConfiguration *configuration = [SPDYProtocol currentConfiguration];
        NSUInteger size = configuration.sessionPoolSize;
        _pendingCount = size;
        _sessions = [[NSMutableArray alloc] initWithCapacity:size];
        for (NSUInteger i = 0; i < size; i++) {
            SPDYSession *session = [[SPDYSession alloc] initWithOrigin:origin
                                                              delegate:manager
                                                         configuration:configuration
                                                              cellular:cellular
                                                                 error:pError];
            if (!session) {
                return nil;
            }
            [_sessions addObject:session];
        }
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
