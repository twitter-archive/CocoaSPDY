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

typedef enum {
    SPDYOriginEndpointTypeDirect,
    SPDYOriginEndpointTypeHttpProxy,
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

- (id)initWithOrigin:(SPDYOrigin *)origin;

- (SPDYOriginEndpoint *)getCurrentEndpoint;

- (bool)moveToNextEndpoint;

@end
