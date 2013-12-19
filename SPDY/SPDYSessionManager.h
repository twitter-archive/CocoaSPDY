//
//  SPDYSessionManager.h
//  SPDY
//
//  Copyright (c) 2013 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>

@class SPDYConfiguration;
@class SPDYSession;

@interface SPDYSessionManager : NSObject
+ (void)setConfiguration:(SPDYConfiguration *)configuration;
+ (SPDYSession *)sessionForURL:(NSURL *)url error:(NSError **)pError;
+ (void)sessionClosed:(SPDYSession *)session;
@end
