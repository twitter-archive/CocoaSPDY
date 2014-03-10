//
//  SPDYOrigin.m
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

@interface SPDYOrigin ()
- (id)initCopyWithScheme:(NSString *)scheme
                    host:(NSString *)host
                    port:(in_port_t)port
           serialization:(NSString *)serialization;
@end

@implementation SPDYOrigin
{
    NSString *_serialization;
}

- (id)initWithString:(NSString *)urlString error:(NSError **)pError
{
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    return [self initWithURL:url error:pError];
}

- (id)initWithURL:(NSURL *)url error:(NSError **)pError
{
    return [self initWithScheme:url.scheme
                           host:url.host
                           port:url.port.unsignedShortValue
                          error:pError];
}

- (id)initWithScheme:(NSString *)scheme
                host:(NSString *)host
                port:(in_port_t)port
               error:(NSError **)pError
{
    self = [super init];
    if (self) {
        _scheme = [scheme lowercaseString];
        if (![_scheme isEqualToString:@"http"] && ![_scheme isEqualToString:@"https"]) {
            if (pError) {
                NSString *message = [[NSString alloc] initWithFormat:@"unsupported scheme (%@) - only http and https are supported", scheme];
                NSDictionary *info = @{ NSLocalizedDescriptionKey: message };
                *pError = [[NSError alloc] initWithDomain:NSURLErrorDomain
                                                     code:NSURLErrorBadURL
                                                 userInfo:info];
            }
            return nil;
        }

        if (host) {
            _host = [host lowercaseString];
        } else {
            if (pError) {
                NSString *message = @"host must be specified";
                NSDictionary *info = @{ NSLocalizedDescriptionKey: message };
                *pError = [[NSError alloc] initWithDomain:NSURLErrorDomain
                                                     code:NSURLErrorBadURL
                                                 userInfo:info];
            }
            return nil;
        }

        if (port == 0) {
            _port = [_scheme isEqualToString:@"http"] ? 80 : 443;
        } else {
            _port = port;
        }

        _serialization = [[NSString alloc] initWithFormat:@"%@://%@:%u", _scheme, _host, _port];
    }
    return self;
}

- (id)initCopyWithScheme:(NSString *)scheme
                    host:(NSString *)host
                    port:(in_port_t)port
           serialization:(NSString *)serialization
{
    self = [super init];
    if (self) {
        _scheme = scheme;
        _host = host;
        _port = port;
        _serialization = serialization;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<SPDYOrigin: %@>", _serialization];
}

- (NSUInteger)hash
{
    return [_serialization hash];
}

- (BOOL)isEqual:(id)object
{
    return self == object || (
        [object isMemberOfClass:[self class]] &&
            [_serialization isEqualToString:((SPDYOrigin *)object)->_serialization]
    );
}

- (id)copyWithZone:(NSZone *)zone
{
    SPDYOrigin *copy = [[SPDYOrigin allocWithZone:zone] initCopyWithScheme:[_scheme copyWithZone:zone]
                                                                      host:[_host copyWithZone:zone]
                                                                      port:_port
                                                             serialization:[_serialization copyWithZone:zone]];
    return copy;
}

@end
