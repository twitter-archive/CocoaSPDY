//
//  SPDYOriginEndpoint.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <Foundation/Foundation.h>

@class SPDYOrigin;

// Some clarification:
//
// What Apple calls an "HTTPS" proxy, kCFProxyTypeHTTPS, means it is used for https:// requests. It
// is still a HTTP proxy, but requires the use of the CONNECT message, since that is the only way
// to establish a TLS session with the origin. SPDY requires TLS.
//
// An "HTTP" proxy, kCFProxyTypeHTTP, as defined on by Apple, is an HTTP proxy that does not use a
// CONNECT  message. We don't support those.
//
// Direct, kCFProxyTypeNone, means no proxy.
//
// As far as I can tell, there is no way to configure a proxy that requires a TLS session
// to connect to it, which would serve to obscure the CONNECT destination. If we could support that,
// the name would be something like SPDYOriginEndpointTypeTlsHttpsProxy.

typedef enum {
    SPDYOriginEndpointTypeDirect,
    SPDYOriginEndpointTypeHttpsProxy
} SPDYOriginEndpointType;

@interface SPDYOriginEndpoint : NSObject

@property (nonatomic, readonly) SPDYOrigin *origin;
@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) in_port_t port;
@property (nonatomic, readonly) NSString *user;
@property (nonatomic, readonly) NSString *password;
@property (nonatomic, readonly) SPDYOriginEndpointType type;

- (id)initWithHost:(NSString *)host
              port:(in_port_t)port
              user:(NSString *)user
          password:(NSString *)password
              type:(SPDYOriginEndpointType)type
            origin:(SPDYOrigin *)origin;

@end

@interface SPDYOriginEndpointManager : NSObject

@property (nonatomic, readonly) SPDYOrigin *origin;
@property (nonatomic, readonly) NSUInteger remaining;
@property (nonatomic, readonly) BOOL needsResolving;

- (id)initWithOrigin:(SPDYOrigin *)origin;

- (SPDYOriginEndpoint *)getCurrentEndpoint;

- (BOOL)moveToNextEndpoint;

- (CFRunLoopSourceRef)resolveUsingBlock:(void (^)(BOOL success))block;

@end
