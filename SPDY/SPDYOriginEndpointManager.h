//
//  SPDYOriginEndpointManager.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

@class SPDYOrigin;
@class SPDYOriginEndpoint;

@interface SPDYOriginEndpointManager : NSObject

@property (nonatomic, readonly) SPDYOrigin *origin;
@property (nonatomic, readonly) SPDYOriginEndpoint *endpoint;
@property (nonatomic, readonly) NSUInteger remaining;

- (id)initWithOrigin:(SPDYOrigin *)origin;
- (void)resolveEndpointsWithCompletionHandler:(void (^)())completionHandler;
- (SPDYOriginEndpoint *)moveToNextEndpoint;

@end
