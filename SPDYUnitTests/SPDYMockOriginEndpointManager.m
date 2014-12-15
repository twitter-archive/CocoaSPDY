//
//  SPDYMockOriginEndpointTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import "SPDYMockOriginEndpointManager.h"

@implementation SPDYMockOriginEndpointManager

- (NSDictionary *)_proxyGetSystemSettings
{
    // Don't need to hook this, will hook into next layer
    return nil;
}

- (NSArray *)_proxyGetListFromSettings:(NSDictionary *)systemProxySettings
{
    return _mock_proxyList;
}

@end

