//
//  SPDYOriginEndpointTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYOrigin.h"
#import "SPDYOriginEndpoint.h"

@interface SPDYOriginEndpointTest : SenTestCase
@end

@implementation SPDYOriginEndpointTest

- (void)testInit
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://twitter.com:443" error:&error];
    SPDYOriginEndpoint *endpoint = [[SPDYOriginEndpoint alloc] initWithHost:@"1.2.3.4"
                                                                      port:8888
                                                                      user:@"user"
                                                                  password:@"pass"
                                                                      type:SPDYOriginEndpointTypeHttpsProxy
                                                                    origin:origin];
    NSLog(@"%@", endpoint); // ensure description doesn't crash
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", @"actual: %@", endpoint.host);
    STAssertEquals(endpoint.port, (in_port_t)8888, @"actual: %@", endpoint.port);
    STAssertEqualObjects(endpoint.user, @"user", @"actual: %@", endpoint.user);
    STAssertEqualObjects(endpoint.password, @"pass", @"actual: %@", endpoint.password);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, @"actual: %@", endpoint.type);
    STAssertEqualObjects(endpoint.origin, origin, @"actual: %@", endpoint.origin);
}

// TODO: need tests for the SPDYOriginEndpointManager. Specifically need tests for the proxy
// configuration code. That will require a lock of mocks and crafting of proxy config data.

@end
