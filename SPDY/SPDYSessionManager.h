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
@class SPDYStreamManager;

@interface SPDYSessionManager : NSObject

+ (SPDYSessionManager *)localManagerForOrigin:(SPDYOrigin *)origin;
- (void)queueStream:(SPDYStream *)stream;

@end
