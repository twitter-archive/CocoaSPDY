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

@class SPDYOrigin;

// Some clarification:
//
// What Apple calls an "HTTPS" proxy, kCFProxyTypeHTTPS, means it is used for https:// requests. It
// is still a HTTP proxy, but requires the use of the CONNECT message, since that is the only way
// to establish an opaque session, as required by SPDY, with the origin.
//
// An "HTTP" proxy, kCFProxyTypeHTTP, as defined by Apple, is an HTTP proxy that does not use a
// CONNECT message. We can't support those.
//
// Direct, kCFProxyTypeNone, means no proxy.
//
// As far as I can tell, there is no system-supported way to configure a proxy that requires a TLS
// session to connect to it, which would serve to obscure the CONNECT destination. This is
// potentially a feature we could add later, though it would be up to the app to supply the
// configuration. If we did, the name would be something like SPDYOriginEndpointTypeTlsHttpsProxy.

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
