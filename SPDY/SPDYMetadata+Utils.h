//
//  SPDYMetadata+Utils.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import "SPDYProtocol.h"

// Private readwrite property accessors for CocoaSPDY internal usage.
@interface SPDYMetadata ()

@property (nonatomic) NSUInteger blockedMs;
@property (nonatomic) BOOL cellular;
@property (nonatomic) NSUInteger connectedMs;
@property (nonatomic, copy) NSString *hostAddress;
@property (nonatomic) NSUInteger hostPort;
@property (nonatomic) NSInteger latencyMs;
@property (nonatomic) SPDYProxyStatus proxyStatus;
@property (nonatomic) NSUInteger rxBytes;
@property (nonatomic) NSUInteger txBytes;
@property (nonatomic) NSUInteger streamId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic) BOOL viaProxy;
@property (nonatomic) NSTimeInterval timeSessionConnected;
@property (nonatomic) NSTimeInterval timeStreamCreated;
@property (nonatomic) NSTimeInterval timeStreamRequestStarted;
@property (nonatomic) NSTimeInterval timeStreamRequestLastHeader;
@property (nonatomic) NSTimeInterval timeStreamRequestFirstData;
@property (nonatomic) NSTimeInterval timeStreamRequestLastData;
@property (nonatomic) NSTimeInterval timeStreamRequestEnded;
@property (nonatomic) NSTimeInterval timeStreamResponseStarted;
@property (nonatomic) NSTimeInterval timeStreamResponseLastHeader;
@property (nonatomic) NSTimeInterval timeStreamResponseFirstData;
@property (nonatomic) NSTimeInterval timeStreamResponseLastData;
@property (nonatomic) NSTimeInterval timeStreamResponseEnded;
@property (nonatomic) NSTimeInterval timeStreamClosed;

@end

// Private helper utilities
@interface SPDYMetadata (Utils)

+ (void)setMetadata:(SPDYMetadata *)metadata forAssociatedDictionary:(NSMutableDictionary *)dictionary;
+ (SPDYMetadata *)metadataForAssociatedDictionary:(NSDictionary *)dictionary;

@end