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

@class SPDYConfiguration;
@class SPDYOrigin;
@class SPDYProtocol;
@class SPDYSessionManager;
@class SPDYSession;
@class SPDYStream;

@protocol SPDYSessionDelegate <NSObject>
- (void)session:(SPDYSession *)session capacityIncreased:(NSUInteger)capacity;
- (void)session:(SPDYSession *)session connectedToNetwork:(bool)cellular;
- (void)session:(SPDYSession *)session refusedStream:(SPDYStream *)stream;
- (void)sessionClosed:(SPDYSession *)session;
@end

@interface SPDYSession : NSObject

@property (nonatomic, weak) id<SPDYSessionDelegate> delegate;
@property (nonatomic, readonly) SPDYOrigin *origin;
@property (nonatomic, assign, readonly) NSUInteger capacity;
@property (nonatomic, assign, readonly) NSUInteger load;
@property (nonatomic, readonly) bool isCellular;
@property (nonatomic, readonly) bool isConnected;
@property (nonatomic, readonly) bool isEstablished;
@property (nonatomic, readonly) bool isOpen;

- (id)initWithOrigin:(SPDYOrigin *)origin
            delegate:(id<SPDYSessionDelegate>)delegate
       configuration:(SPDYConfiguration *)configuration
            cellular:(bool)cellular
               error:(NSError **)pError;
- (void)openStream:(SPDYStream *)stream;
- (void)close;

@end
