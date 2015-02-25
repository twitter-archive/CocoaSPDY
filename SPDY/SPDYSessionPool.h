//
//  SPDYSessionPool.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <Foundation/Foundation.h>

@class SPDYSession;
@class SPDYSessionManager;

@interface SPDYSessionPool : NSObject

@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, assign) NSUInteger pendingCount;

- (bool)contains:(SPDYSession *)session;
- (void)add:(SPDYSession *)session;
- (NSUInteger)count;
- (NSUInteger)remove:(SPDYSession *)session;
- (SPDYSession *)nextSession;

@end
