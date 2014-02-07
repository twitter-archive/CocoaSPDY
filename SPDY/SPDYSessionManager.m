//
//  SPDYSessionManager.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "SPDYOrigin.h"
#import "SPDYSessionManager.h"
#import "SPDYProtocol.h"
#import "SPDYSession.h"

@interface SPDYSessionManager ()
+ (NSMutableDictionary *)activeSessions;
@end

static NSString *const SPDYSessionManagerKey = @"com.twitter.SPDYSessionManager";
static SPDYConfiguration *currentConfiguration;

@implementation SPDYSessionManager

+ (void)initialize
{
    currentConfiguration = [SPDYConfiguration defaultConfiguration];
}

+ (NSMutableDictionary *)activeSessions
{
    NSMutableDictionary *threadDictionary = [NSThread currentThread].threadDictionary;
    NSMutableDictionary *activeSessions = threadDictionary[SPDYSessionManagerKey];
    if (!activeSessions) {
        activeSessions = [NSMutableDictionary new];
        threadDictionary[SPDYSessionManagerKey] = activeSessions;
    }
    return activeSessions;
}

+ (void)setConfiguration:(SPDYConfiguration *)configuration
{
    currentConfiguration = [configuration copy];
}

+ (SPDYSession *)sessionForURL:(NSURL *)url error:(NSError **)pError
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithURL:url error:pError];
    NSMutableDictionary *activeSessions = [SPDYSessionManager activeSessions];
    SPDYSession *session = activeSessions[origin];
    if (!session || !session.isOpen) {
        session = [[SPDYSession alloc] initWithOrigin:origin
                                        configuration:currentConfiguration
                                                error:pError];
        if (session) {
            activeSessions[origin] = session;
        }
    }
    return session;
}

+ (void)sessionClosed:(SPDYSession *)session
{
    SPDYOrigin *origin = session.origin;
    NSMutableDictionary *activeSessions = [SPDYSessionManager activeSessions];
    if (activeSessions[origin] == session) {
        [activeSessions removeObjectForKey:origin];
    }
}

@end
