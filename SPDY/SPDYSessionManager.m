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

static void SPDYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);

@interface SPDYSessionManager () <SPDYSessionDelegate, SPDYStreamDelegate>
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
    volatile BOOL _cellular;
    NSArray *_runLoopModes;
    NSTimer *_dispatchTimer;
    SCNetworkReachabilityRef _rRef;
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
        _basePool = [[SPDYSessionPool alloc] init];
        _wwanPool = [[SPDYSessionPool alloc] init];
        _cellular = NO;

        NSString *currentMode = [[NSRunLoop currentRunLoop] currentMode];
        if (currentMode == nil || [currentMode isEqual:NSDefaultRunLoopMode]) {
            currentMode = NSDefaultRunLoopMode;
            _runLoopModes = @[NSDefaultRunLoopMode];
        } else {
            _runLoopModes = @[NSDefaultRunLoopMode, currentMode];
        }

        SCNetworkReachabilityContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
        _rRef = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, origin.host.UTF8String);

        if (SCNetworkReachabilitySetCallback(_rRef, SPDYReachabilityCallback, &context)) {
            SCNetworkReachabilityScheduleWithRunLoop(_rRef, CFRunLoopGetCurrent(), (__bridge CFStringRef)currentMode);
        } else {
            SPDY_WARNING(@"unable to register for reachability callbacks");
        }

        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags(_rRef, &flags)) {
            [self _updateReachability:flags];
        } else {
            SPDY_WARNING(@"unable to get current reachability");
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
        SPDY_DEBUG(@"%@ created", session);
    }
}

- (void)_dispatch
{
    if (_dispatchTimer) _dispatchTimer = nil;
    if (_pendingStreams.count == 0) return;

    bool cellular = _cellular;
    SPDYSessionPool *activePool = cellular ? _wwanPool : _basePool;

    if (activePool.count == 0) {
        SPDY_DEBUG(@"filling %@ session pool", cellular ? @"WLAN" : @"WIFI");
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
            SPDY_DEBUG(@"filling %@ session pool due to no session", cellular ? @"WLAN" : @"WIFI");
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
    // Note: we should move the session to the correct pool, if necessary, but I'm not
    // yet confident that's always safe to do, since the reachability info only reports
    // "reachable" plus optionally "wwan". It doesn't really tell us when both wifi and
    // wwan are available (it reports wifi when both are present), and I don't know
    // all the conditions when a socket will use one or the other. However, there are
    // normal edge cases where we DO need to move the session, so let's try it.

    SPDYConfiguration *configuration = [SPDYProtocol currentConfiguration];
    BOOL moveSession = configuration.enforceSessionPoolCorrectness;

    if ([_basePool contains:session]) {
        _basePool.pendingCount -= 1;
        if (cellular) {
            SPDY_WARNING(@"%@ is in wifi pool but socket connected over cellular, %@moving", session, moveSession ? @"" : @"not ");
            if (moveSession) {
                [_basePool remove:session];
                [_wwanPool add:session];
            }
        }
    } else if ([_wwanPool contains:session]) {
        _wwanPool.pendingCount -= 1;
        if (!cellular) {
            SPDY_WARNING(@"%@ is in cellular pool but socket connected over wifi, %@ moving", session, moveSession ? @"" : @"not ");
            if (moveSession) {
                [_wwanPool remove:session];
                [_basePool add:session];
            }
        }
    }

    [self _dispatch];
}

- (void)sessionClosed:(SPDYSession *)session
{
    SPDY_DEBUG(@"%@ closed", session);

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
        SPDY_DEBUG(@"reachability updated: offline, flags 0x%x", flags);
        return;
    }

#if TARGET_OS_IPHONE
    _cellular = (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0;
#endif
    SPDY_DEBUG(@"reachability updated: %@, flags 0x%x", _cellular ? @"WWAN" : @"WIFI", flags);

    [self _dispatch];
}

@end


static void SPDYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *pManager)
{
    if (pManager) {
        @autoreleasepool {
            SPDYSessionManager * volatile manager = (__bridge SPDYSessionManager *)pManager;
            [manager _updateReachability:flags];
        }
    }
}
