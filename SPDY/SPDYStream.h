//
//  SPDYStream.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>
#import "SPDYDefinitions.h"

@class SPDYProtocol;
@class SPDYStream;
@protocol SPDYExtendedDelegate;

@protocol SPDYStreamDataDelegate <NSObject>
- (void)streamDataAvailable:(SPDYStream *)stream;
- (void)streamFinished:(SPDYStream *)stream;
@end

@interface SPDYStream : NSObject
@property (nonatomic, weak) id<NSURLProtocolClient> client;
@property (nonatomic, weak) id<SPDYStreamDataDelegate> dataDelegate;
@property (nonatomic, weak) id<SPDYExtendedDelegate> extendedDelegate;
@property (nonatomic) NSData *data;
@property (nonatomic) NSInputStream *dataStream;
@property (nonatomic, weak) NSURLRequest *request;
@property (nonatomic, weak) SPDYProtocol *protocol;
@property (nonatomic) SPDYStreamId streamId;
@property (nonatomic) uint8_t priority;
@property (nonatomic) bool local;
@property (nonatomic) bool localSideClosed;
@property (nonatomic) bool remoteSideClosed;
@property (nonatomic, readonly) bool closed;
@property (nonatomic) bool receivedReply;
@property (nonatomic, readonly) bool hasDataAvailable;
@property (nonatomic, readonly) bool hasDataPending;
@property (nonatomic) uint32_t sendWindowSize;
@property (nonatomic) uint32_t receiveWindowSize;
@property (nonatomic) uint32_t sendWindowSizeLowerBound;
@property (nonatomic) uint32_t receiveWindowSizeLowerBound;
@property (nonatomic) NSUInteger txBytes;
@property (nonatomic) NSUInteger rxBytes;

- (id)initWithProtocol:(SPDYProtocol *)protocol dataDelegate:(id<SPDYStreamDataDelegate>)delegate;
- (void)startWithStreamId:(SPDYStreamId)id sendWindowSize:(uint32_t)sendWindowSize receiveWindowSize:(uint32_t)receiveWindowSize;
- (NSData *)readData:(NSUInteger)length error:(NSError **)pError;
- (void)closeWithError:(NSError *)error;
- (void)closeWithMetadata:(NSDictionary *)metadata;
- (bool)didReceiveResponse:(NSDictionary *)headers error:(NSError **)pError;
- (bool)didLoadData:(NSData *)data error:(NSError **)pError;
@end
