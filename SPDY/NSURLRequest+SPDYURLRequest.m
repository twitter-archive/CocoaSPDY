//
//  NSURLRequest+SPDYURLRequest.m
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

#import <objc/runtime.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYProtocol.h"

@implementation NSURLRequest (SPDYURLRequest)

- (NSUInteger)SPDYPriority
{
    return [[SPDYProtocol propertyForKey:@"SPDYPriority" inRequest:self] unsignedIntegerValue];
}

- (NSTimeInterval)SPDYDeferrableInterval
{
    return [[SPDYProtocol propertyForKey:@"SPDYDeferrableInterval" inRequest:self] doubleValue];
}

- (BOOL)SPDYBypass
{
    return [[SPDYProtocol propertyForKey:@"SPDYBypass" inRequest:self] boolValue];
}

- (NSInputStream *)SPDYBodyStream
{
    return [SPDYProtocol propertyForKey:@"SPDYBodyStream" inRequest:self];
}

- (NSString *)SPDYBodyFile
{
    return [SPDYProtocol propertyForKey:@"SPDYBodyFile" inRequest:self];
}

- (NSURLSession *)SPDYURLSession
{
    return [self spdy_indirectObjectForKey:@"SPDYURLSession"];
}

- (NSString *)SPDYURLSessionRequestIdentifier
{
    return [SPDYProtocol propertyForKey:@"SPDYURLSession" inRequest:self];
}

- (NSDictionary *)allSPDYHeaderFields
{
    NSDictionary *httpHeaders = self.allHTTPHeaderFields;
    NSURL *url = self.URL;

    static NSSet *invalidKeys;
    static NSSet *reservedKeys;
    static dispatch_once_t initialized;
    dispatch_once(&initialized, ^{
        invalidKeys = [[NSSet alloc] initWithObjects:
            @"connection", @"keep-alive", @"proxy-connection", @"transfer-encoding", nil
        ];

        reservedKeys = [[NSSet alloc] initWithObjects:
            @"method", @"path", @"version", @"host", @"scheme", nil
        ];
    });

    NSString *escapedPath = CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
            kCFAllocatorDefault,
            (__bridge CFStringRef)url.path,
            NULL,
            CFSTR("?"),
            kCFStringEncodingUTF8));

    NSMutableString *path = [[NSMutableString alloc] initWithString:escapedPath];
    NSString *query = url.query;
    if (query) {
        [path appendFormat:@"?%@", query];
    }

    NSString *fragment = url.fragment;
    if (fragment) {
        [path appendFormat:@"#%@", fragment];
    }

    // Allow manually-set headers to override request properties
    NSMutableDictionary *spdyHeaders = [[NSMutableDictionary alloc] initWithDictionary:@{
        @":method"  : self.HTTPMethod,
        @":path"    : path,
        @":version" : @"HTTP/1.1",
        @":host"    : url.host,
        @":scheme"  : url.scheme
    }];

    // Proxy all application-provided HTTP headers, if allowed, over to SPDY headers.
    for (NSString *key in httpHeaders) {
        NSString *lowercaseKey = [key lowercaseString];
        if (![invalidKeys containsObject:lowercaseKey]) {
            if ([reservedKeys containsObject:lowercaseKey]) {
                spdyHeaders[[@":" stringByAppendingString:lowercaseKey]] = httpHeaders[key];
            } else {
                spdyHeaders[lowercaseKey] = httpHeaders[key];
            }
        }
    }

    // The current implementation here will always override cookies retrieved from cookie storage
    // by those set manually in headers.
    // TODO: confirm behavior for Cocoa's API and send cookies from both sources, as appropriate
    BOOL cookiesOn = NO;
    NSHTTPCookieStorage *cookieStore = nil;

    NSURLSessionConfiguration *config = self.SPDYURLSession.configuration;
    if (config) {
        if (config.HTTPShouldSetCookies) {
            cookieStore = config.HTTPCookieStorage;
            cookiesOn = (cookieStore != nil);
        }
    } else {
        cookiesOn = self.HTTPShouldHandleCookies;
        cookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    }

    if (cookiesOn) {
        NSString *requestCookies = spdyHeaders[@"cookie"];
        if (!requestCookies || requestCookies.length == 0) {
            NSArray *cookies = [cookieStore cookiesForURL:url];
            if (cookies.count > 0) {
                NSDictionary *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
                NSString *cookie = cookieHeaders[@"Cookie"];
                if (cookie) {
                    spdyHeaders[@"cookie"] = cookie;
                }
            }
        }
    }

    return spdyHeaders;
}

- (id)spdy_indirectObjectForKey:(NSString *)key
{
    NSString *contextString = [SPDYProtocol propertyForKey:key inRequest:self];
    return (contextString) ? objc_getAssociatedObject(contextString, @selector(spdy_indirectObjectForKey:)) : nil;
}

@end

@implementation NSMutableURLRequest (SPDYURLRequest)

- (void)setSPDYPriority:(NSUInteger)priority
{
    [SPDYProtocol setProperty:@(priority) forKey:@"SPDYPriority" inRequest:self];
}

- (void)setSPDYDeferrableInterval:(NSTimeInterval)deferrableInterval
{
    [SPDYProtocol setProperty:@(deferrableInterval) forKey:@"SPDYDeferrableInterval" inRequest:self];
}

- (void)setSPDYBypass:(BOOL)bypass
{
    [SPDYProtocol setProperty:@(bypass) forKey:@"SPDYBypass" inRequest:self];
}

- (void)setSPDYBodyStream:(NSInputStream *)SPDYBodyStream
{
    if (SPDYBodyStream == nil) {
        [SPDYProtocol removePropertyForKey:@"SPDYBodyStream" inRequest:self];
    } else {
        [SPDYProtocol setProperty:SPDYBodyStream forKey:@"SPDYBodyStream" inRequest:self];
    }
}

- (void)setSPDYBodyFile:(NSString *)SPDYBodyFile
{
    if (SPDYBodyFile == nil) {
        [SPDYProtocol removePropertyForKey:@"SPDYBodyFile" inRequest:self];
    } else {
        [SPDYProtocol setProperty:SPDYBodyFile forKey:@"SPDYBodyFile" inRequest:self];
    }
}

- (void)setSPDYURLSession:(NSURLSession *)SPDYURLSession
{
    [self spdy_setIndirectObject:SPDYURLSession forKey:@"SPDYURLSession"];
}

- (void)spdy_setIndirectObject:(id)object forKey:(NSString *)key
{
    if (object == nil) {
        [SPDYProtocol removePropertyForKey:key inRequest:self];
    } else {
        NSString *contextString = [[NSUUID UUID] UUIDString];
        objc_setAssociatedObject(contextString, @selector(spdy_indirectObjectForKey:), object, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [SPDYProtocol setProperty:contextString forKey:key inRequest:self];
    }
}

@end
