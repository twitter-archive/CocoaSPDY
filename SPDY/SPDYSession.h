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
@class SPDYStream;

@interface SPDYSession : NSObject

@property (nonatomic, readonly) SPDYOrigin *origin;
@property (nonatomic, readonly) bool isCellular;
@property (nonatomic, readonly) bool isOpen;
@property (nonatomic, readonly) NSInteger latencyMs;

+ (NSMutableDictionary *)getMetadataForSession:(SPDYSession *)session stream:(SPDYStream *)stream;
+ (NSError *)addMetadata:(NSMutableDictionary *)metadata toError:(NSError *)error;

- (id)initWithOrigin:(SPDYOrigin *)origin
       configuration:(SPDYConfiguration *)configuration
            cellular:(bool)cellular
               error:(NSError **)pError;
- (void)issueRequest:(SPDYProtocol *)protocol;
- (void)cancelRequest:(SPDYProtocol *)protocol;
- (void)close;

@end
