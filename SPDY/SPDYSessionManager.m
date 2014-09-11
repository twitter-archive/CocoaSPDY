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
@end

static NSString *const SPDYSessionManagerKey = @"com.twitter.SPDYSessionManager";
static volatile bool reachabilityIsWWAN;

#if TARGET_OS_IPHONE
static char *const SPDYReachabilityQueue = "com.twitter.SPDYReachabilityQueue";

static SCNetworkReachabilityRef reachabilityRef;
static dispatch_queue_t reachabilityQueue;

static void SPDYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);
#endif

@interface SPDYSessionPool : NSObject
- (id)initWithOrigin:(SPDYOrigin *)origin configuration:(SPDYConfiguration *)configuration size:(NSUInteger)size error:(NSError **)pError;
- (NSUInteger)remove:(SPDYSession *)session;
- (SPDYSession *)next;
@end

@implementation SPDYSessionPool
{
    NSMutableArray *_sessions;
}

- (id)initWithOrigin:(SPDYOrigin *)origin configuration:(SPDYConfiguration *)configuration size:(NSUInteger)size error:(NSError **)pError
{
    self = [super init];
    if (self) {
        _sessions = [[NSMutableArray alloc] initWithCapacity:size];
        for (NSUInteger i = 0; i < size; i++) {
            SPDYSession *session = [[SPDYSession alloc] initWithOrigin:origin
                                                         configuration:configuration
                                                              cellular:reachabilityIsWWAN
                                                                 error:pError];
            if (!session) {
                return nil;
            }
            [_sessions addObject:session];
        }
    }
    return self;
}

- (NSUInteger)remove:(SPDYSession *)session
{
    [_sessions removeObject:session];
    return _sessions.count;
}

- (SPDYSession *)next
{
    if (_sessions.count == 0) return nil;
    
    SPDYSession *session = nil;
    do {
        session = _sessions[0];
    } while (session && !session.isOpen && [self remove:session] > 0);
    if (!session.isOpen) session = nil; // No open sessions in the pool
    
    // Rotate
    if (_sessions.count > 1) {
        [_sessions removeObjectAtIndex:0];
        [_sessions addObject:session];
    }
    return session;
}

@end

@implementation SPDYSessionManager
{
    NSArray *_poolTables;
    dispatch_queue_t _dispatchQueue;
}

+ (void)initialize
{
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

- (instancetype)init
{
    self = [super init];
    if (self) {
        _configuration = [SPDYConfiguration defaultConfiguration];
        _dispatchQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (SPDYSession *)sessionForURL:(NSURL *)url error:(NSError **)pError
{
    __block SPDYSession *session = nil;
    dispatch_sync(_dispatchQueue, ^{
        SPDYOrigin *origin = [[SPDYOrigin alloc] initWithURL:url error:pError];
        NSMutableDictionary *poolTable = [self _sessionPoolTable:reachabilityIsWWAN];
        SPDYSessionPool *pool = poolTable[origin];
        session = [pool next];
        if (!session) {
            pool = [[SPDYSessionPool alloc] initWithOrigin:origin
                                             configuration:self.configuration
                                                      size:self.configuration.sessionPoolSize
                                                     error:pError];
            if (pool) {
                poolTable[origin] = pool;
                session = [pool next];
            }
        }
        
        NSAssert(session != nil, @"session should not be nil");
        SPDY_DEBUG(@"Retrieving session: %@", session);
        if ([self.delegate respondsToSelector:@selector(sessionManager:willStartSession:forURL:)]) {
            [self.delegate sessionManager:self willStartSession:session forURL:url];
        }
    });
    return session;
}

- (void)removeSession:(SPDYSession *)session
{
    NSParameterAssert(session);
    dispatch_sync(_dispatchQueue, ^{
        SPDY_DEBUG(@"Removing session: %@", session);
        SPDYOrigin *origin = session.origin;
        if ([self.delegate respondsToSelector:@selector(sessionManager:willStartSession:forURL:)]) {
            [self.delegate sessionManager:self willRemoveSession:session];
        }
        NSMutableDictionary *poolTable = [self _sessionPoolTable:session.isCellular];
        SPDYSessionPool *pool = poolTable[origin];
        if (pool && [pool remove:session] == 0) {
            [poolTable removeObjectForKey:origin];
        }
    });
}

- (NSArray *)allSessions
{
    NSMutableArray *sessions = [NSMutableArray new];
    [sessions addObjectsFromArray:[[_poolTables[0] allValues] valueForKeyPath:@"@distinctUnionOfArrays.sessions"]];
    [sessions addObjectsFromArray:[[_poolTables[1] allValues] valueForKeyPath:@"@distinctUnionOfArrays.sessions"]];
    return sessions;
}

- (NSMutableDictionary *)_sessionPoolTable:(bool)cellular
{
    if (!_poolTables) {
        _poolTables = @[
            [NSMutableDictionary new],
            [NSMutableDictionary new]  // WWAN
        ];
    }

    SPDY_DEBUG(@"using %@ session pool", cellular ? @"cellular" : @"standard");
    return _poolTables[cellular ? 1 : 0];
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
