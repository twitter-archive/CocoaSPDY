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
#import "SPDYOrigin.h"
#import "SPDYStream.h"

@class SPDYConfiguration;
@class SPDYSession;
@class SPDYStreamManager;
@class SPDYSessionManager;

extern NSString *const SPDYSessionManagerDidInitializeNotification;

@protocol SPDYSessionManagerDelegate <NSObject>

@optional

- (void)sessionManager:(SPDYSessionManager *)sessionManager sessionDidConnect:(SPDYSession *)session;
- (void)sessionManager:(SPDYSessionManager *)sessionManager sessionWillClose:(SPDYSession *)session withError:(NSError *)error;
- (void)sessionManager:(SPDYSessionManager *)sessionManager sessionDidClose:(SPDYSession *)session;

@end

@interface SPDYSessionManager : NSObject

+ (SPDYSessionManager *)localManagerForOrigin:(SPDYOrigin *)origin;
- (id)initWithOrigin:(SPDYOrigin *)origin;

@property (nonatomic, readonly) SPDYOrigin *origin;
@property (nonatomic, weak) id<SPDYSessionManagerDelegate> delegate;

- (void)queueStream:(SPDYStream *)stream;
- (NSArray *)allSessions;

@end
