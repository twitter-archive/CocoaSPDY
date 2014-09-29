//
//  SPDYProtocol.m
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

#import "SPDYProtocol.h"
#import "SPDYCommonLogger.h"
#import "SPDYOrigin.h"
#import "SPDYSession.h"
#import "SPDYSessionManager.h"
#import "SPDYTLSTrustEvaluator.h"
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYStream.h"

NSString *const SPDYStreamErrorDomain = @"SPDYStreamErrorDomain";
NSString *const SPDYSessionErrorDomain = @"SPDYSessionErrorDomain";
NSString *const SPDYCodecErrorDomain = @"SPDYCodecErrorDomain";
NSString *const SPDYSocketErrorDomain = @"SPDYSocketErrorDomain";
NSString *const SPDYOriginRegisteredNotification = @"SPDYOriginRegisteredNotification";
NSString *const SPDYOriginUnregisteredNotification = @"SPDYOriginUnregisteredNotification";
NSString *const SPDYMetadataVersionKey = @"x-spdy-version";
NSString *const SPDYMetadataStreamIdKey = @"x-spdy-stream-id";
NSString *const SPDYMetadataStreamRxBytesKey = @"x-spdy-stream-rx-bytes";
NSString *const SPDYMetadataStreamTxBytesKey = @"x-spdy-stream-tx-bytes";
NSString *const SPDYMetadataSessionLatencyKey = @"x-spdy-session-latency";

static char *const SPDYConfigQueue = "com.twitter.SPDYConfigQueue";
static dispatch_once_t initConfig;
static dispatch_queue_t configQueue;

@implementation SPDYProtocol
{
    SPDYStream *_stream;
}

static SPDYConfiguration *currentConfiguration;
static id<SPDYTLSTrustEvaluator> trustEvaluator;

+ (void)initialize
{
    dispatch_once(&initConfig, ^{
        configQueue = dispatch_queue_create(SPDYConfigQueue, DISPATCH_QUEUE_CONCURRENT);
        currentConfiguration = [SPDYConfiguration defaultConfiguration];
    });

#ifdef DEBUG
    SPDY_WARNING(@"loaded DEBUG build of SPDY framework");
#endif
}

+ (SPDYConfiguration *)currentConfiguration
{
    __block SPDYConfiguration *configuration;
    dispatch_sync(configQueue, ^{
        configuration = [currentConfiguration copy];
    });
    return configuration;
}

+ (void)setConfiguration:(SPDYConfiguration *)configuration
{
    dispatch_barrier_async(configQueue, ^{
        currentConfiguration = [configuration copy];
    });
}

+ (void)setLogger:(id<SPDYLogger>)logger
{
    [SPDYCommonLogger setLogger:logger];
}

+ (void)setTLSTrustEvaluator:(id<SPDYTLSTrustEvaluator>)evaluator
{
    SPDY_INFO(@"register trust evaluator: %@", evaluator);
    dispatch_barrier_async(configQueue, ^{
        trustEvaluator = evaluator;
    });
}

+ (id<SPDYTLSTrustEvaluator>)sharedTLSTrustEvaluator
{
    __block id<SPDYTLSTrustEvaluator> evaluator;
    dispatch_sync(configQueue, ^{
        evaluator = trustEvaluator;
    });
    return evaluator;
}

#pragma mark NSURLProtocol implementation

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }

    return !request.SPDYBypass && ![request valueForHTTPHeaderField:@"x-spdy-bypass"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSURLRequest *request = self.request;
    SPDY_INFO(@"start loading %@", request.URL.absoluteString);

    NSError *error;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithURL:request.URL error:&error];
    if (origin) {
        SPDYSessionManager *manager = [SPDYSessionManager localManagerForOrigin:origin];
        _stream = [[SPDYStream alloc] initWithProtocol:self];
        [manager queueStream:_stream];
    }

    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    }
}

- (void)stopLoading
{
    SPDY_INFO(@"stop loading %@", self.request.URL.absoluteString);

    if (_stream && !_stream.closed) {
        [_stream cancel];
    }
}

@end

#pragma mark NSURLSession implementation

@implementation SPDYURLSessionProtocol
@end


//__attribute__((constructor))
//static void registerSPDYURLConnectionProtocol() {
//    @autoreleasepool {
//        [NSURLProtocol registerClass:[SPDYURLConnectionProtocol class]];
//    }
//}

#pragma mark NSURLConnection implementation

@implementation SPDYURLConnectionProtocol
static dispatch_once_t initOrigins;
static NSMutableSet *origins;

+ (void)load
{
    // +[NSURLProtocol registerClass] is not threadsafe, so register before
    // requests start getting made.
    @autoreleasepool {
        [NSURLProtocol registerClass:self];
    }
}

+ (void)initialize
{
    dispatch_once(&initOrigins, ^{
        origins = [[NSMutableSet alloc] init];
    });
}

+ (void)registerOrigin:(NSString *)originString
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:originString error:nil];
    SPDY_INFO(@"register origin: %@", origin);
    dispatch_barrier_async(configQueue, ^{
        [origins addObject:origin];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginRegisteredNotification object:nil userInfo:@{ @"origin": originString }];
        SPDY_DEBUG(@"origin registered: %@", origin);
    });
}

+ (void)unregisterOrigin:(NSString *)originString
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:originString error:nil];
    dispatch_barrier_async(configQueue, ^{
        if ([origins containsObject:origin]) {
            [origins removeObject:origin];
            [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification object:nil userInfo:@{ @"origin": originString }];
            SPDY_DEBUG(@"origin unregistered: %@", origin);
        }
    });
}

+ (void)unregisterAll
{
    dispatch_barrier_async(configQueue, ^{
        [origins removeAllObjects];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification object:nil userInfo:@{ @"origin": @"*" }];
        SPDY_DEBUG(@"unregistered all origins");
    });
}

#pragma mark NSURLProtocol implementation

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    if (![super canInitWithRequest:request]) {
        return NO;
    }

    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithURL:request.URL error:nil];
    if (!origin) {
        return NO;
    }

    __block bool originRegistered;
    dispatch_sync(configQueue, ^{
        originRegistered = [origins containsObject:origin];
    });
    return originRegistered;
}

@end

#pragma mark Configuration

@implementation SPDYConfiguration

static SPDYConfiguration *defaultConfiguration;

+ (void)initialize
{
    defaultConfiguration = [[SPDYConfiguration alloc] init];
    defaultConfiguration.headerCompressionLevel = 9;
    defaultConfiguration.sessionPoolSize = 1;
    defaultConfiguration.sessionReceiveWindow = 10485760;
    defaultConfiguration.streamReceiveWindow = 10485760;
    defaultConfiguration.enableSettingsMinorVersion = NO;
    defaultConfiguration.tlsSettings = @{ /* use Apple default TLS settings */ };
    defaultConfiguration.connectTimeout = 60.0;
    defaultConfiguration.enableTCPNoDelay = NO;
}

+ (SPDYConfiguration *)defaultConfiguration
{
    return [defaultConfiguration copy];
}

- (id)copyWithZone:(NSZone *)zone
{
    SPDYConfiguration *copy = [[SPDYConfiguration allocWithZone:zone] init];
    copy.headerCompressionLevel = _headerCompressionLevel;
    copy.sessionPoolSize = _sessionPoolSize;
    copy.sessionReceiveWindow = _sessionReceiveWindow;
    copy.streamReceiveWindow = _streamReceiveWindow;
    copy.enableSettingsMinorVersion = _enableSettingsMinorVersion;
    copy.tlsSettings = _tlsSettings;
    copy.connectTimeout = _connectTimeout;
    copy.enableTCPNoDelay = _enableTCPNoDelay;
    return copy;
}

@end
