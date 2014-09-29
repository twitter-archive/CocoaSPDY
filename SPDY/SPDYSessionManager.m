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
#import "SPDYStreamManager.h"
#import <arpa/inet.h>
#import "SPDYCommonLogger.h"
#import "SPDYOrigin.h"
#import "SPDYProtocol.h"
#import "SPDYSession.h"
#import "SPDYSessionManager.h"
#import "SPDYStreamManager.h"
#import "SPDYStream.h"
#import "NSURLRequest+SPDYURLRequest.h"

static NSString *const SPDYSessionManagerKey = @"com.twitter.SPDYSessionManager";
static volatile bool reachabilityIsWWAN;

#if TARGET_OS_IPHONE
static char *const SPDYReachabilityQueue = "com.twitter.SPDYReachabilityQueue";

static SCNetworkReachabilityRef reachabilityRef;
static dispatch_queue_t reachabilityQueue;

static void SPDYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);
#endif

@interface SPDYSessionPool : NSObject
@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, assign) NSUInteger pendingCount;
- (id)initWithOrigin:(SPDYOrigin *)origin manager:(SPDYSessionManager *)manager error:(NSError **)pError;
- (NSUInteger)remove:(SPDYSession *)session;
- (SPDYSession *)nextSession;
@end

@interface SPDYSessionManager () <SPDYSessionDelegate, SPDYStreamDelegate>
- (void)session:(SPDYSession *)session capacityIncreased:(NSUInteger)capacity;
- (void)session:(SPDYSession *)session connectedToNetwork:(bool)cellular;
- (void)sessionClosed:(SPDYSession *)session;
- (void)streamCanceled:(SPDYStream *)stream;
@end

@implementation SPDYSessionPool
{
    NSMutableArray *_sessions;
}

- (id)initWithOrigin:(SPDYOrigin *)origin manager:(SPDYSessionManager *)manager error:(NSError **)pError
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

    // Rotate
    if (_sessions.count > 1) {
        [_sessions removeObjectAtIndex:0];
        [_sessions addObject:session];
    }

    NSAssert(session.isOpen, @"Should never return closed sessions.");
    return session;
}

@end

@implementation SPDYSessionManager
{
    SPDYOrigin *_origin;
    SPDYSessionPool *_basePool;
    SPDYSessionPool *_wwanPool;
    SPDYStreamManager *_pendingStreams;
    NSArray *_runLoopModes;
    NSTimer *_dispatchTimer;
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

+ (SPDYSessionManager *)localManagerForOrigin:(SPDYOrigin *)origin
{
    NSMutableDictionary *threadDictionary = [NSThread currentThread].threadDictionary;
    NSMutableDictionary *originDictionary = threadDictionary[SPDYSessionManagerKey];
    if (!originDictionary) {
        threadDictionary[SPDYSessionManagerKey] = [NSMutableDictionary new];
    }

    SPDYSessionManager *manager = originDictionary[origin];
    if (!manager) {
        manager = [[SPDYSessionManager alloc] initWithOrigin:origin];
        originDictionary[origin] = manager;
    }

    return manager;
}

- (id)initWithOrigin:(SPDYOrigin *)origin
{
    self = [super init];
    if (self) {
        _origin = origin;
        _pendingStreams = [[SPDYStreamManager alloc] init];
        NSString *currentMode = [[NSRunLoop currentRunLoop] currentMode];
        if ([currentMode isEqual:NSDefaultRunLoopMode]) {
            _runLoopModes = @[NSDefaultRunLoopMode];
        } else {
            _runLoopModes = @[NSDefaultRunLoopMode, currentMode];
        }
    }
    return self;
}

- (void)queueStream:(SPDYStream *)stream
{
    NSAssert(stream.protocol != nil, @"can only enqueue local streams");

    SPDY_INFO(@"queueing request: %@", stream.request.URL);
    [_pendingStreams addStream:stream];
    stream.delegate = self;

    NSTimeInterval deferrableInterval = stream.request.SPDYDeferrableInterval;
    if (deferrableInterval > 0) {
        CFAbsoluteTime maxDelayThreshold = CFAbsoluteTimeGetCurrent() + deferrableInterval;

        if (!_dispatchTimer) {
            _dispatchTimer = [NSTimer timerWithTimeInterval:deferrableInterval
                                                     target:self
                                                   selector:@selector(_dispatch)
                                                   userInfo:nil
                                                    repeats:NO];
            for (NSString *runLoopMode in _runLoopModes) {
                CFRunLoopAddTimer(CFRunLoopGetCurrent(), (__bridge CFRunLoopTimerRef)_dispatchTimer, (__bridge CFStringRef)runLoopMode);
            }
        } else {
            CFAbsoluteTime currentDelayTreshold = CFRunLoopTimerGetNextFireDate((__bridge CFRunLoopTimerRef)_dispatchTimer);

            if (currentDelayTreshold < CFAbsoluteTimeGetCurrent()) {
                [self _dispatch];
            } else if (maxDelayThreshold < currentDelayTreshold) {
                CFRunLoopTimerSetNextFireDate((__bridge CFRunLoopTimerRef)_dispatchTimer, maxDelayThreshold);
            }
        }
    } else {
        [self _dispatch];
    }
}

#pragma mark SPDYStreamDelegate

- (void)streamCanceled:(SPDYStream *)stream
{
    NSAssert(_pendingStreams[stream.protocol], @"stream delegate must be managing stream");

    [_pendingStreams removeStreamForProtocol:stream.protocol];
}

- (void)streamClosed:(SPDYStream *)stream
{
    NSAssert(false, @"session manager must never manage open streams");
}

- (void)streamDataAvailable:(SPDYStream *)stream
{
    NSAssert(false, @"session manager must never manage open streams");
}

- (void)streamDataFinished:(SPDYStream *)stream
{
    NSAssert(false, @"session manager must never manage open streams");
}

#pragma mark private methods

- (void)_dispatch
{
    if (_dispatchTimer) _dispatchTimer = nil;
    if (_pendingStreams.count == 0) return;

    SPDYSessionPool * __strong *activePool = reachabilityIsWWAN ? &_wwanPool : &_basePool;

    if (!*activePool || (*activePool).count == 0) {
        NSError *pError;
        *activePool = [[SPDYSessionPool alloc] initWithOrigin:_origin manager:self error:&pError];
        if (pError) {
            for (SPDYStream *stream in _pendingStreams) {
                SPDYProtocol *protocol = stream.protocol;
                [protocol.client URLProtocol:protocol didFailWithError:pError];
            }
            [_pendingStreams removeAllStreams];
        }

        return;
    }

    SPDYSession *session;
    double holdback = 1.0 / ((*activePool).pendingCount + 1);
    double allocation = 1.0 - holdback;

    for (int i = 0; _pendingStreams.count > 0 && i < (*activePool).count; i++) {
        session = [*activePool nextSession];
        if (!session.isConnected) continue;

        NSUInteger count = MIN(session.capacity, _pendingStreams.count);
        if (count > 0) {
            // Load-balance when a session has recently connected
            if (!session.isEstablished) {
                count = MIN(count, (NSUInteger)ceil(allocation * _pendingStreams.localCount - holdback * session.load));
            }

            for (int j = 0; j < count; j++) {
                SPDYStream *stream = [_pendingStreams nextPriorityStream];
                [_pendingStreams removeStreamForProtocol:stream.protocol];
                [session openStream:stream];
            }
        }
    }
}

#pragma mark SPDYSessionDelegate

- (void)session:(SPDYSession *)session capacityIncreased:(NSUInteger)capacity
{
    [self _dispatch];
}

- (void)session:(SPDYSession *)session connectedToNetwork:(bool)cellular
{
    if ([_basePool contains:session]) {
        _basePool.pendingCount -= 1;
        if (cellular) {
            [_basePool remove:session];
            [_wwanPool add:session];
        }
    } else if ([_wwanPool contains:session]) {
        _wwanPool.pendingCount -= 1;
        if (!cellular) {
            [_wwanPool remove:session];
            [_basePool add:session];
        }
    }

    [self _dispatch];
}

- (void)sessionClosed:(SPDYSession *)session
{
    SPDY_DEBUG(@"session closed: %@", session);
    SPDYSessionPool * __strong *pool = session.isCellular ? &_wwanPool : &_basePool;
    if (*pool && [*pool remove:session] == 0) {
        *pool = nil;
    }
}

- (void)session:(SPDYSession *)session refusedStream:(SPDYStream *)stream
{
    SPDY_INFO(@"re-queueing request: %@", stream.protocol.request.URL);
    [_pendingStreams addStream:stream];
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
