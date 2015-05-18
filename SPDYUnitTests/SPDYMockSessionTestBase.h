//
//  SPDYMockSession.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import "SPDYDefinitions.h"
#import "SPDYProtocol.h"
#import "SPDYStream.h"

@class SPDYFrameEncoder;
@class SPDYMockFrameDecoderDelegate;
@class SPDYMockFrameEncoderDelegate;
@class SPDYMockURLProtocolClient;
@class SPDYOrigin;
@class SPDYProtocol;
@class SPDYPushStreamManager;
@class SPDYSession;
@class SPDYStream;

typedef void (^SPDYAsyncTestCallback)();

@interface SPDYMockStreamDelegate : NSObject<SPDYStreamDelegate>
@property(nonatomic) int calledStreamCanceled;
@property(nonatomic) int calledStreamClosed;
@property(nonatomic) int calledStreamDataAvailable;
@property(nonatomic) int calledStreamDataFinished;
@property(nonatomic, strong) SPDYStream *lastStream;
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, copy) SPDYAsyncTestCallback callback;
@end

@interface SPDYMockSessionTestBase : XCTestCase
{
    // Note on frameEncoder:
    // Used locally for encoding frames. Whatever gets encoded manually in the frameEncoder
    // here *must* get decoded by the session, else the zlib library gets out of sync and you'll
    // get Z_DATA_ERROR errors ("incorrect header check").
    // Note on URLRequest and protocolRequest:
    // We *must* maintain references to these for the whole test.
    SPDYOrigin *_origin;
    SPDYSession *_session;
    NSMutableURLRequest *_URLRequest;
    NSMutableArray *_protocolList;
    SPDYFrameEncoder *_testEncoder;
    SPDYMockFrameEncoderDelegate *_testEncoderDelegate;
    SPDYMockFrameDecoderDelegate *_mockDecoderDelegate;
    SPDYMockURLProtocolClient *_mockURLProtocolClient;
    SPDYMockStreamDelegate *_mockStreamDelegate;
}

- (void)setUp;
- (void)tearDown;

- (SPDYProtocol *)createProtocol;
- (SPDYStream *)createStream;
- (void)makeSessionReadData:(NSData *)data;

- (SPDYStream *)mockSynStreamAndReplyWithId:(SPDYStreamId)streamId last:(bool)last;
- (void)mockServerSynReplyWithId:(SPDYStreamId)streamId last:(BOOL)last;
- (void)mockServerGoAwayWithLastGoodId:(SPDYStreamId)lastGoodStreamId statusCode:(SPDYSessionStatus)statusCode;
- (void)mockServerDataWithId:(SPDYStreamId)streamId data:(NSData *)data last:(BOOL)last;
- (void)mockServerSynStreamWithId:(uint32_t)streamId last:(BOOL)last;
- (void)mockServerSynStreamWithId:(uint32_t)streamId last:(BOOL)last headers:(NSDictionary *)headers;
- (void)mockServerHeadersFrameForPushWithId:(uint32_t)streamId last:(BOOL)last;
- (void)mockServerHeadersFrameWithId:(uint32_t)streamId headers:(NSDictionary *)headers last:(BOOL)last;
- (void)mockServerDataFrameWithId:(uint32_t)streamId length:(NSUInteger)length last:(BOOL)last;
- (void)mockPushResponseWithTwoDataFrames;
- (void)mockPushResponseWithTwoDataFramesWithId:(SPDYStreamId)streamId;

@end
