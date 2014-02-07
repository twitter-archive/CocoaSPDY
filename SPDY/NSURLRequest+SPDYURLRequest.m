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

#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYProtocol.h"

@implementation NSURLRequest (SPDYURLRequest)

- (NSUInteger)SPDYPriority
{
    return [[SPDYProtocol propertyForKey:@"SPDYPriority" inRequest:self] unsignedIntegerValue];
}

- (BOOL)SPDYDiscretionary
{
    return [[SPDYProtocol propertyForKey:@"SPDYDiscretionary" inRequest:self] boolValue];
}

- (NSInputStream *)SPDYBodyStream
{
    return [SPDYProtocol propertyForKey:@"SPDYBodyStream" inRequest:self];
}

- (NSString *)SPDYBodyFile
{
    return [SPDYProtocol propertyForKey:@"SPDYBodyFile" inRequest:self];
}

- (NSDictionary *)allSPDYHeaderFields
{
    NSDictionary *httpHeaders = self.allHTTPHeaderFields;

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

    NSMutableString *path = [[NSMutableString alloc] initWithString:self.URL.path];
    NSString *query = self.URL.query;
    if (query) {
        [path appendFormat:@"?%@", query];
    }

    NSString *fragment = self.URL.fragment;
    if (fragment) {
        [path appendFormat:@"#%@", fragment];
    }

    // Allow manually-set headers to override request properties
    NSMutableDictionary *spdyHeaders = [[NSMutableDictionary alloc] initWithDictionary:@{
        @":method"  : self.HTTPMethod,
        @":path"    : path,
        @":version" : @"HTTP/1.1",
        @":host"    : self.URL.host,
        @":scheme"  : self.URL.scheme
    }];

    bool hasBodyData = (self.HTTPBody || self.HTTPBodyStream
        || self.SPDYBodyStream || self.SPDYBodyFile);
    if ([self.HTTPMethod isEqualToString:@"POST"] && hasBodyData) {
        spdyHeaders[@"content-type"] = @"application/x-www-form-urlencoded";
    }

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

    if (self.HTTPShouldHandleCookies) {
        NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:self.URL];
        if (cookies.count > 0) {
            NSDictionary *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
            spdyHeaders[@"cookie"] = cookieHeaders[@"Cookie"];
        }
    }

    // Request properties will take precedence over manually-set headers
    // [spdyHeaders addEntriesFromDictionary:@{
    //     @":method"  : self.HTTPMethod,
    //     @":path"    : path,
    //     @":version" : @"HTTP/1.1",
    //     @":host"    : self.URL.host,
    //     @":scheme"  : self.URL.scheme
    // }];

    return spdyHeaders;
}

@end

@implementation NSMutableURLRequest (SPDYURLRequest)

- (NSUInteger)SPDYPriority
{
    return [[SPDYProtocol propertyForKey:@"SPDYPriority" inRequest:self] unsignedIntegerValue];
}

- (void)setSPDYPriority:(NSUInteger)priority
{
    [SPDYProtocol setProperty:@(priority) forKey:@"SPDYPriority" inRequest:self];
}

- (BOOL)SPDYDiscretionary
{
    return [[SPDYProtocol propertyForKey:@"SPDYDiscretionary" inRequest:self] boolValue];
}

- (void)setSPDYDiscretionary:(BOOL)Discretionary
{
    [SPDYProtocol setProperty:@(Discretionary) forKey:@"SPDYDiscretionary" inRequest:self];
}

- (NSInputStream *)SPDYBodyStream
{
    return [SPDYProtocol propertyForKey:@"SPDYBodyStream" inRequest:self];
}

- (void)setSPDYBodyStream:(NSInputStream *)SPDYBodyStream
{
    [SPDYProtocol setProperty:SPDYBodyStream forKey:@"SPDYBodyStream" inRequest:self];
}

- (NSString *)SPDYBodyFile
{
    return [SPDYProtocol propertyForKey:@"SPDYBodyFile" inRequest:self];
}

- (void)setSPDYBodyFile:(NSString *)SPDYBodyFile
{
    [SPDYProtocol setProperty:SPDYBodyFile forKey:@"SPDYBodyFile" inRequest:self];
}

@end
