//
//  SPDYMockSessionManager.h
//  SPDY
//
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier on 11/30/15.
//

#import <Foundation/Foundation.h>
#import "SPDYSessionManager.h"

@class SPDYPushStreamManager;
@class SPDYStream;

typedef void (^SPDYMockSessionManagerStreamQueuedCallback)(SPDYStream *stream);

@interface SPDYMockSessionManager : SPDYSessionManager

#pragma mark Mock methods

@property (nonatomic, copy) SPDYMockSessionManagerStreamQueuedCallback streamQueuedBlock;

+ (void)performSwizzling:(BOOL)performSwizzling;
+ (SPDYMockSessionManager *)shared;

#pragma mark SPDYSessionManager methods

@property (nonatomic, readonly) SPDYPushStreamManager *pushStreamManager;

- (void)queueStream:(SPDYStream *)stream;

@end
