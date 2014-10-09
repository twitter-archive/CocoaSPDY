//
//  SPDYSession.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>
#import "SPDYStream.h"

@class SPDYProtocol;
@class SPDYConfiguration;
@class SPDYOrigin;
@class SPDYSocket;
@protocol SPDYSessionDelegate;

@interface SPDYSession : NSObject <SPDYStreamPushClient>

@property (nonatomic, readonly) SPDYOrigin *origin;
@property (nonatomic, readonly) bool isCellular;
@property (nonatomic, readonly) bool isOpen;
@property (nonatomic, weak) id<SPDYSessionDelegate> delegate;
@property (nonatomic, readonly) SPDYSocket *socket;

- (id)initWithOrigin:(SPDYOrigin *)origin
       configuration:(SPDYConfiguration *)configuration
            cellular:(bool)cellular
               error:(NSError **)pError;
- (void)issueRequest:(SPDYProtocol *)protocol;
- (void)cancelRequest:(SPDYProtocol *)protocol;
- (void)close;

@end

@protocol SPDYSessionDelegate <NSObject>

- (void)session:(SPDYSession *)session didReceivePushResponse:(NSURLResponse *)response data:(NSData *)data;
- (void)session:(SPDYSession *)session willCloseWithError:(NSError *)error;

@end
