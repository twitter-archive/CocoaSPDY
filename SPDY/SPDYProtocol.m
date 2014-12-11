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

#import <arpa/inet.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYCanonicalRequest.h"
#import "SPDYCommonLogger.h"
#import "SPDYMetadata.h"
#import "SPDYOrigin.h"
#import "SPDYProtocol.h"
#import "SPDYSession.h"
#import "SPDYSessionManager.h"
#import "SPDYStream.h"
#import "SPDYTLSTrustEvaluator.h"

NSString *const SPDYStreamErrorDomain = @"SPDYStreamErrorDomain";
NSString *const SPDYSessionErrorDomain = @"SPDYSessionErrorDomain";
NSString *const SPDYCodecErrorDomain = @"SPDYCodecErrorDomain";
NSString *const SPDYSocketErrorDomain = @"SPDYSocketErrorDomain";
NSString *const SPDYOriginRegisteredNotification = @"SPDYOriginRegisteredNotification";
NSString *const SPDYOriginUnregisteredNotification = @"SPDYOriginUnregisteredNotification";
NSString *const SPDYMetadataVersionKey = @"x-spdy-version";
NSString *const SPDYMetadataSessionRemoteAddressKey = @"x-spdy-session-remote-address";
NSString *const SPDYMetadataSessionRemotePortKey = @"x-spdy-session-remote-port";
NSString *const SPDYMetadataSessionViaProxyKey = @"x-spdy-session-via-proxy";
NSString *const SPDYMetadataSessionLatencyKey = @"x-spdy-session-latency";
NSString *const SPDYMetadataStreamBlockedMsKey = @"x-spdy-stream-blocked-ms";
NSString *const SPDYMetadataStreamConnectedMsKey = @"x-spdy-stream-connected-ms";
NSString *const SPDYMetadataStreamIdKey = @"x-spdy-stream-id";
NSString *const SPDYMetadataStreamRxBytesKey = @"x-spdy-stream-rx-bytes";
NSString *const SPDYMetadataStreamTxBytesKey = @"x-spdy-stream-tx-bytes";

static char *const SPDYConfigQueue = "com.twitter.SPDYConfigQueue";

static NSMutableDictionary *aliases;
static NSMutableDictionary *certificates;
static dispatch_queue_t configQueue;
static dispatch_once_t initConfig;

@implementation SPDYProtocol
{
    SPDYStream *_stream;
}

static SPDYConfiguration *currentConfiguration;
static id<SPDYTLSTrustEvaluator> trustEvaluator;

+ (void)initialize
{
    dispatch_once(&initConfig, ^{
        aliases = [[NSMutableDictionary alloc] init];
        certificates = [[NSMutableDictionary alloc] init];
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

+ (id<SPDYLogger>)currentLogger
{
    return [SPDYCommonLogger currentLogger];
}

+ (void)setLoggerLevel:(SPDYLogLevel)level
{
    [SPDYCommonLogger setLoggerLevel:level];
}

+ (SPDYLogLevel)currentLoggerLevel
{
    return [SPDYCommonLogger currentLoggerLevel];
}

+ (void)setTLSTrustEvaluator:(id<SPDYTLSTrustEvaluator>)evaluator
{
    SPDY_INFO(@"register trust evaluator: %@", evaluator);
    dispatch_barrier_async(configQueue, ^{
        trustEvaluator = evaluator;
    });
}

+ (bool)evaluateServerTrust:(SecTrustRef)trust forHost:(NSString *)host {
    __block id<SPDYTLSTrustEvaluator> evaluator;
    __block NSString *namedHost;

    dispatch_sync(configQueue, ^{
        evaluator = trustEvaluator;
        namedHost = certificates[host];
    });

    if (evaluator == nil) return YES;
    if (namedHost != nil) host = namedHost;

    return [evaluator evaluateServerTrust:trust forHost:host];
}

+ (NSDictionary *)metadataForResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:httpResponse.allHeaderFields];
    return [metadata dictionary];
}

+ (NSDictionary *)metadataForError:(NSError *)error
{
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:error.userInfo];
    return [metadata dictionary];
}

+ (void)registerAlias:(NSString *)aliasString forOrigin:(NSString *)originString
{
    SPDYOrigin *alias = [[SPDYOrigin alloc] initWithString:aliasString error:nil];
    if (!alias) {
        SPDY_ERROR(@"invalid origin: %@", aliasString);
        return;
    }

    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:originString error:nil];
    if (!origin) {
        SPDY_ERROR(@"invalid origin: %@", originString);
        return;
    }

    SPDY_INFO(@"register alias: %@", aliasString);
    dispatch_barrier_async(configQueue, ^{
        aliases[alias] = origin;

        // Use the alias hostname for TLS validation if the aliased origin contains a bare IP address
        struct in_addr ipTest;
        if (inet_pton(AF_INET, [origin.host cStringUsingEncoding:NSUTF8StringEncoding], &ipTest)) {
            certificates[origin.host] = alias.host;
        }

        NSDictionary *info = @{ @"origin": originString, @"alias": aliasString };
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginRegisteredNotification
                                                            object:nil
                                                          userInfo:info];
        SPDY_DEBUG(@"alias registered: %@", alias);
    });
}

+ (void)unregisterAlias:(NSString *)aliasString
{
    SPDYOrigin *alias = [[SPDYOrigin alloc] initWithString:aliasString error:nil];
    if (!alias) {
        SPDY_ERROR(@"invalid origin: %@", aliasString);
        return;
    }

    dispatch_barrier_async(configQueue, ^{
        SPDYOrigin *origin = aliases[alias];
        if (origin) {
            [aliases removeObjectForKey:alias];
            [certificates removeObjectForKey:origin.host];
            [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification
                                                                object:nil
                                                              userInfo:@{ @"alias": aliasString }];
            SPDY_DEBUG(@"alias unregistered: %@", alias);
        }
    });
}

+ (SPDYOrigin *)originForAlias:(SPDYOrigin *)alias
{
    __block SPDYOrigin *origin;
    dispatch_sync(configQueue, ^{
        origin = aliases[alias];
    });
    return origin;
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
    return SPDYCanonicalRequestForRequest(request);
}

- (void)startLoading
{
    NSURLRequest *request = self.request;
    SPDY_INFO(@"start loading %@", request.URL.absoluteString);

    NSError *error;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithURL:request.URL error:&error];
    if (!origin) {
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    SPDYOrigin *aliasedOrigin = [SPDYProtocol originForAlias:origin];
    if (aliasedOrigin) {
        origin = aliasedOrigin;
    }

    SPDYSessionManager *manager = [SPDYSessionManager localManagerForOrigin:origin];
    _stream = [[SPDYStream alloc] initWithProtocol:self];
    [manager queueStream:_stream];
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
    if (!origin) {
        SPDY_ERROR(@"invalid origin: %@", originString);
        return;
    }

    dispatch_barrier_async(configQueue, ^{
        [origins addObject:origin];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginRegisteredNotification
                                                            object:nil
                                                          userInfo:@{ @"origin": originString }];
        SPDY_DEBUG(@"origin registered: %@", origin);
    });
}

+ (void)unregisterOrigin:(NSString *)originString
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:originString error:nil];
    if (!origin) {
        SPDY_ERROR(@"invalid origin: %@", originString);
        return;
    }

    dispatch_barrier_async(configQueue, ^{
        if ([origins containsObject:origin]) {
            [origins removeObject:origin];
            [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification
                                                                object:nil
                                                              userInfo:@{ @"origin": originString }];
            SPDY_DEBUG(@"origin unregistered: %@", origin);
        }
    });
}

+ (void)unregisterAll
{
    dispatch_barrier_async(configQueue, ^{
        [origins removeAllObjects];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification
                                                            object:nil
                                                          userInfo:@{ @"origin": @"*" }];
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

    SPDYOrigin *aliasedOrigin = [SPDYProtocol originForAlias:origin];
    if (aliasedOrigin) {
        origin = aliasedOrigin;
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
    defaultConfiguration.enableProxy = YES;
    defaultConfiguration.proxyHost = nil;
    defaultConfiguration.proxyPort = 0;
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
    copy.enableProxy = _enableProxy;
    copy.proxyHost = _proxyHost;
    copy.proxyPort = _proxyPort;
    return copy;
}

@end
