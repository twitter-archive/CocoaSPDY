//
//  SPDYMockOriginEndpointManager.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier

#import "SPDYOrigin.h"
#import "SPDYOriginEndpointManager.h"

@interface SPDYMockOriginEndpointManager : SPDYOriginEndpointManager
@property NSArray *mock_proxyList;
@end

