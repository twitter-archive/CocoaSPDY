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
#import "SPDYSessionPool.h"
#import "SPDYStreamManager.h"
#import "SPDYStream.h"
#import "NSURLRequest+SPDYURLRequest.h"

static NSString *const SPDYSessionManagerKey = @"com.twitter.SPDYSessionManager";
static volatile bool __cellular;

static char *const SPDYReachabilityQueue = "com.twitter.SPDYReachabilityQueue";

static SCNetworkReachabilityRef reachabilityRef;
static dispatch_queue_t reachabilityQueue;

static void SPDYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);

@interface SPDYSessionManager () <SPDYSessionDelegate, SPDYStreamDelegate>
@property (nonatomic) NSArray *runLoopModes;
@property (nonatomic) NSRunLoop *runLoop;
- (void)session:(SPDYSession *)session capacityIncreased:(NSUInteger)capacity;
- (void)session:(SPDYSession *)session connectedToNetwork:(bool)cellular;
- (void)sessionClosed:(SPDYSession *)session;
- (void)streamCanceled:(SPDYStream *)stream;
@end

@implementation SPDYSessionManager
{
    SPDYOrigin *_origin;
    SPDYSessionPool *_basePool;
    SPDYSessionPool *_wwanPool;
    SPDYStreamManager *_pendingStreams;
    NSArray *_runLoopModes;
    NSRunLoop *_runLoop;
    NSTimer *_dispatchTimer;
    SCNetworkReachabilityRef _rRef;
}

+ (void)initialize
{
    __cellular = NO;

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
}

+ (SPDYSessionManager *)localManagerForOrigin:(SPDYOrigin *)origin
{
    NSMutableDictionary *threadDictionary = [NSThread currentThread].threadDictionary;
    NSMutableDictionary *originDictionary = threadDictionary[SPDYSessionManagerKey];
    if (!originDictionary) {
        originDictionary = [NSMutableDictionary new];
        threadDictionary[SPDYSessionManagerKey] = originDictionary;
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
        _runLoop = [NSRunLoop currentRunLoop];
        _basePool = [[SPDYSessionPool alloc] init];
        _wwanPool = [[SPDYSessionPool alloc] init];

        NSString *currentMode = [_runLoop currentMode];
        if (currentMode == nil || [currentMode isEqual:NSDefaultRunLoopMode]) {
            _runLoopModes = @[NSDefaultRunLoopMode];
        } else {
            _runLoopModes = @[NSDefaultRunLoopMode, currentMode];
        }

        SCNetworkReachabilityContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
        _rRef = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, origin.host.UTF8String);

        if (SCNetworkReachabilitySetCallback(reachabilityRef, SPDYReachabilityCallback, &context)) {
            SCNetworkReachabilitySetDispatchQueue(reachabilityRef, reachabilityQueue);
        }
    }
    return self;
}

- (void)dealloc
{
    if (_rRef) {
        SCNetworkReachabilitySetDispatchQueue(_rRef, NULL);
        CFRelease(_rRef);
    }
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
    stream.delegate = nil;
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

- (void)_fillSessionPool:(SPDYSessionPool *)sessionPool cellular:(bool)cellular
{
    NSParameterAssert(sessionPool);
    NSError *error = nil;

    SPDYConfiguration *configuration = [SPDYProtocol currentConfiguration];
    NSUInteger size = configuration.sessionPoolSize;

    while (sessionPool.count < size) {
        SPDYSession *session = [[SPDYSession alloc] initWithOrigin:_origin
                                                          delegate:self
                                                     configuration:configuration
                                                          cellular:cellular
                                                             error:&error];

        if (!session || error) {
            if (sessionPool.count == 0) {
                for (SPDYStream *stream in _pendingStreams) {
                    stream.delegate = nil;
                    SPDYProtocol *protocol = stream.protocol;
                    [protocol.client URLProtocol:protocol didFailWithError:error];
                }
                [_pendingStreams removeAllStreams];
                return;
            } else {
                SPDY_WARNING(@"failed allocating extra session to pool: %@", error);
                continue;
            }
        }

        [sessionPool add:session];
        sessionPool.pendingCount += 1;
    }
}

- (void)_dispatch
{
    if (_dispatchTimer) _dispatchTimer = nil;
    if (_pendingStreams.count == 0) return;

    bool cellular = __cellular;
    SPDYSessionPool *activePool = cellular ? _wwanPool : _basePool;

    if (activePool.count == 0) {
        [self _fillSessionPool:activePool cellular:cellular];
        // Once the sessions finish connecting, we'll dispatch again. Until then let's keep
        // the pending streams pending.
        return;
    }

    SPDYSession *session;
    double allocation = 1.0 / (activePool.pendingCount + 1);
    double holdback = 1.0 - allocation;

    for (int i = 0; _pendingStreams.count > 0 && i < activePool.count; i++) {
        session = [activePool nextSession];

        // TODO: by all accounts this should never happen; keeping cleanup temporarily
        NSAssert(session, @"session pool should have sessions");
        if (!session) {
            [self _fillSessionPool:activePool cellular:cellular];
            return;
        }

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
                stream.delegate = nil;
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
            SPDY_WARNING(@"moving session from wifi to cellular pool based on socket status");
            [_basePool remove:session];
            [_wwanPool add:session];
        }
    } else if ([_wwanPool contains:session]) {
        _wwanPool.pendingCount -= 1;
        if (!cellular) {
            SPDY_WARNING(@"moving session from cellular to wifi pool based on socket status");
            [_wwanPool remove:session];
            [_basePool add:session];
        }
    }

    [self _dispatch];
}

- (void)sessionClosed:(SPDYSession *)session
{
    SPDY_DEBUG(@"session closed: %@", session);

    if ([_basePool contains:session]) {
        [_basePool remove:session];
    } else if ([_wwanPool contains:session]) {
        [_wwanPool remove:session];
    }

//    SPDYSessionPool * __strong *pool = session.isCellular ? &_wwanPool : &_basePool;
//    if (*pool && [*pool remove:session] == 0) {
//        *pool = nil;
//    }
}

- (void)session:(SPDYSession *)session refusedStream:(SPDYStream *)stream
{
    SPDY_INFO(@"re-queueing request: %@", stream.protocol.request.URL);
    [_pendingStreams addStream:stream];
    stream.delegate = self;
}

- (void)_updateReachability:(SCNetworkReachabilityFlags)flags
{
    if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
        SPDY_DEBUG(@"reachability updated: offline");
        return;
    }

#if TARGET_OS_IPHONE
    __cellular = (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0;
#endif
    SPDY_DEBUG(@"reachability updated: %@", __cellular ? @"WWAN" : @"WLAN");

    [self _dispatch];
}

@end


static void SPDYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *pManager)
{
    if (pManager) {
        @autoreleasepool {
            SPDYSessionManager * volatile manager = (__bridge SPDYSessionManager *)pManager;
            [manager.runLoop performSelector:@selector(_updateReachability:)
                                      target:manager
                                    argument:nil
                                       order:0
                                       modes:manager.runLoopModes];
        }
    }
}
