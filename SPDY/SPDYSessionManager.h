//
//  SPDYSessionManager.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>

@class SPDYConfiguration;
@class SPDYSession;
@protocol SPDYSessionManagerDelegate;

@interface SPDYSessionManager : NSObject

@property (nonatomic, weak) id<SPDYSessionManagerDelegate> delegate;
@property (nonatomic, strong) SPDYConfiguration *configuration;

- (SPDYSession *)sessionForURL:(NSURL *)url error:(NSError **)pError;
- (void)removeSession:(SPDYSession *)session;

@end

@protocol SPDYSessionManagerDelegate <NSObject>

- (void)sessionManager:(SPDYSessionManager *)sessionManager willStartSession:(SPDYSession *)session forURL:(NSURL *)URL;
- (void)sessionManager:(SPDYSessionManager *)sessionManager willRemoveSession:(SPDYSession *)session;

@end
