//
//  SPDYOriginEndpoint.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "SPDYCommonLogger.h"
#import "SPDYOrigin.h"
#import "SPDYOriginEndpoint.h"

@implementation SPDYOriginEndpoint

- (id)initWithHost:(NSString *)host
              port:(in_port_t)port
              user:(NSString *)user
          password:(NSString *)password
              type:(SPDYOriginEndpointType)type
            origin:(SPDYOrigin *)origin
{
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _user = [user copy];
        _password = [password copy];
        _type = type;
        _origin = origin;
    }
    return self;
}

- (NSString *)description
{
    if (_type == SPDYOriginEndpointTypeDirect) {
        return [NSString stringWithFormat:@"<SPDYOriginEndpoint: %@:%d origin:%@>",
                                          _host, _port,
                                          _origin];
    } else {
        return [NSString stringWithFormat:@"<SPDYOriginEndpoint: %@:%d (%@ proxy%@) origin:%@>",
                                          _host, _port,
                                          _type == SPDYOriginEndpointTypeHttpsProxy ? @"https" : @"unknown",
                                          _user ? @" with credentials" : @"",
                                          _origin];
    }
}
@end

