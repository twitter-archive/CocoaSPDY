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

#import <SystemConfiguration/SystemConfiguration.h>
#import <arpa/inet.h>
#import "SPDYCommonLogger.h"
#import "SPDYOrigin.h"
#import "SPDYProtocol.h"
#import "SPDYSession.h"
#import "SPDYSessionManager.h"

@interface SPDYSessionManager ()
+ (NSMutableDictionary *)_sessionPool:(bool)network;
@end

static NSString *const SPDYSessionManagerKey = @"com.twitter.SPDYSessionManager";
static SPDYConfiguration *currentConfiguration;
static volatile bool reachabilityIsWWAN;

#if TARGET_OS_IPHONE
static char *const SPDYReachabilityQueue = "com.twitter.SPDYReachabilityQueue";

static SCNetworkReachabilityRef reachabilityRef;
static dispatch_queue_t reachabilityQueue;

static void SPDYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);
#endif

@implementation SPDYSessionManager

+ (void)initialize
{
    currentConfiguration = [SPDYConfiguration defaultConfiguration];
    reachabilityIsWWAN = NO;

#if TARGET_OS_IPHONE
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = (uint8_t)sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;

    SCNetworkReachabilityContext context = {0, NULL, NULL, NULL, NULL};
    reachabilityRef = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);

    if (SCNetworkReachabilitySetCallback(reachabilityRef, SPDYReachabilityCallback, &context)) {
        reachabilityQueue = dispatch_queue_create(SPDYReachabilityQueue, DISPATCH_QUEUE_SERIAL);
        SCNetworkReachabilitySetDispatchQueue(reachabilityRef, reachabilityQueue);
    }

    dispatch_async(reachabilityQueue, ^{
        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) {
            SPDYReachabilityCallback(reachabilityRef, flags, NULL);
        }
    });
#endif
}

+ (void)setConfiguration:(SPDYConfiguration *)configuration
{
    currentConfiguration = [configuration copy];
}

+ (SPDYSession *)sessionForURL:(NSURL *)url error:(NSError **)pError
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithURL:url error:pError];
    NSMutableDictionary *activeSessions = [SPDYSessionManager _sessionPool:reachabilityIsWWAN];
    SPDYSession *session = activeSessions[origin];
    if (!session || !session.isOpen) {
        session = [[SPDYSession alloc] initWithOrigin:origin
                                        configuration:currentConfiguration
                                             cellular:reachabilityIsWWAN
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
    NSMutableDictionary *activeSessions = [SPDYSessionManager _sessionPool:session.isCellular];
    if (activeSessions[origin] == session) {
        [activeSessions removeObjectForKey:origin];
    }
}

+ (NSMutableDictionary *)_sessionPool:(bool)cellular
{
    NSMutableDictionary *threadDictionary = [NSThread currentThread].threadDictionary;
    NSArray *sessionPools = threadDictionary[SPDYSessionManagerKey];
    if (!sessionPools) {
        sessionPools = @[
            [NSMutableDictionary new],
            [NSMutableDictionary new]  // WWAN
        ];
        threadDictionary[SPDYSessionManagerKey] = sessionPools;
    }

    SPDY_DEBUG(@"using %@ session pool", cellular ? @"cellular" : @"standard");
    return sessionPools[cellular ? 1 : 0];
}

@end

#if TARGET_OS_IPHONE
static void SPDYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info)
{
    // Only update if the network is actually reachable
    if (flags & kSCNetworkReachabilityFlagsReachable) {
        reachabilityIsWWAN = (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0;
        SPDY_DEBUG(@"reachability updated: %@", reachabilityIsWWAN ? @"WWAN" : @"WLAN");
    }
}
#endif
