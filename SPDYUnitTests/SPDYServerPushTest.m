//
//  SPDYServerPushTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Klemen Verdnik on 6/10/14.
//  Modified by Kevin Goodier on 9/19/14.
//

#import <XCTest/XCTest.h>
#import "SPDYOrigin.h"
#import "SPDYSession.h"
#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYFrame.h"
#import "SPDYProtocol.h"
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYMockFrameEncoderDelegate.h"
#import "SPDYMockFrameDecoderDelegate.h"
#import "SPDYMockSessionTestBase.h"
#import "SPDYMockURLProtocolClient.h"

@interface SPDYServerPushTest : SPDYMockSessionTestBase
@end

@implementation SPDYServerPushTest
{
}

#pragma mark Test Helpers

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

#pragma mark Early push error cases tests

- (void)testSYNStreamWithStreamIDZeroRespondsWithSessionError
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client
    [self mockServerSynStreamWithId:0 last:NO];

    // If a client receives a server push stream with stream-id 0, it MUST issue a session error
    // (Section 2.4.2) with the status code PROTOCOL_ERROR.
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)2);
    XCTAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYGoAwayFrame class]]);
    XCTAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYRstStreamFrame class]]);
    XCTAssertEqual(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).statusCode, SPDY_SESSION_PROTOCOL_ERROR);
    XCTAssertEqual(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).lastGoodStreamId, (SPDYStreamId)0);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).statusCode, SPDY_STREAM_PROTOCOL_ERROR);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).streamId, (SPDYStreamId)1);
}

- (void)testSYNStreamWithUnidirectionalFlagUnsetRespondsWithSessionError
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Simulate a server Tx stream SYN_STREAM request (opening a push stream) that's associated
    // with the stream that the client created.
    SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = 2;
    synStreamFrame.unidirectional = NO;
    synStreamFrame.last = NO;
    synStreamFrame.headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/pushed",
            @":status":@"200", @":version":@"http/1.1", @"PushHeader":@"PushValue"};
    synStreamFrame.associatedToStreamId = 1;

    [_testEncoderDelegate clear];
    [_testEncoder encodeSynStreamFrame:synStreamFrame error:nil];
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];

    // @@@ Confirm this is right behavior
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)2);
    XCTAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYGoAwayFrame class]]);
    XCTAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYRstStreamFrame class]]);
    XCTAssertEqual(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).statusCode, SPDY_SESSION_PROTOCOL_ERROR);
    XCTAssertEqual(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).lastGoodStreamId, (SPDYStreamId)0);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).statusCode, SPDY_STREAM_PROTOCOL_ERROR);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).streamId, (SPDYStreamId)1);
}

- (void)testSYNStreamWithAssociatedStreamIdZeroRespondsWithSessionError
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client
    SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = 2;
    synStreamFrame.unidirectional = YES;
    synStreamFrame.last = NO;
    synStreamFrame.headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/pushed",
            @":status":@"200", @":version":@"http/1.1", @"PushHeader":@"PushValue"};
    synStreamFrame.associatedToStreamId = 0;
    [_testEncoderDelegate clear];
    XCTAssertTrue([_testEncoder encodeSynStreamFrame:synStreamFrame error:nil] > 0);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];

    // @@@ Confirm this is right behavior
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)2);
    XCTAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYGoAwayFrame class]]);
    XCTAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYRstStreamFrame class]]);
    XCTAssertEqual(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).statusCode, SPDY_SESSION_PROTOCOL_ERROR);
    XCTAssertEqual(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).lastGoodStreamId, (SPDYStreamId)0);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).statusCode, SPDY_STREAM_PROTOCOL_ERROR);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).streamId, (SPDYStreamId)1);
}

- (void)testSYNStreamWithNoSchemeHeaderRespondsWithReset
 {
     // Exchange initial SYN_STREAM and SYN_REPLY
     [self mockSynStreamAndReplyWithId:1 last:NO];

     NSDictionary *headers = @{/*@":scheme":@"http", */@":host":@"mocked", @":path":@"/pushed"};
     [self mockServerSynStreamWithId:2 last:NO headers:headers];

     // When a client receives a SYN_STREAM from the server without a the ':host', ':scheme', and
     // ':path' headers in the Name/Value section, it MUST reply with a RST_STREAM with error
     // code HTTP_PROTOCOL_ERROR.
     XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)1);
     XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]]);
     XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_PROTOCOL_ERROR);
     XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).streamId, (SPDYStreamId)2);
 }

- (void)testSYNStreamAndAHeadersFrameWithDuplicatesRespondsWithReset
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client
    [self mockServerSynStreamWithId:2 last:NO];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"hello", @"PushHeader2":@"PushValue2"};
    [self mockServerHeadersFrameWithId:2 headers:headers last:NO];

    // If the server sends a HEADER frame containing duplicate headers with a previous HEADERS
    // frame for the same stream, the client must issue a stream error (Section 2.4.2) with error
    // code PROTOCOL ERROR.
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)1);
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]]);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_PROTOCOL_ERROR);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).streamId, (SPDYStreamId)2);
}

- (void)testSYNStreamWithDifferentOriginRespondsWithReset
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Default test origin is "http://mocked:80". Use different scheme for test.
    NSDictionary *headers = @{@":scheme":@"https", @":host":@"mocked", @":path":@"/pushed"};
    [self mockServerSynStreamWithId:2 last:NO headers:headers];

    // Different origin for push, client must refuse
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)1);
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]]);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_REFUSED_STREAM);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).streamId, (SPDYStreamId)2);
}

#pragma mark Simple push callback tests

- (void)testSYNStreamWithStreamIDNonZeroMakesResponseCallback
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];

    SPDYMockURLProtocolClient *pushClient = [self attachToPushRequestWithUrl:@"http://mocked/pushed"].client;
    XCTAssertTrue(pushClient.calledDidReceiveResponse);
    XCTAssertFalse(pushClient.calledDidLoadData);
    XCTAssertFalse(pushClient.calledDidFailWithError);
    XCTAssertFalse(pushClient.calledDidFinishLoading);

    NSHTTPURLResponse *pushResponse = pushClient.lastResponse;
    XCTAssertEqualObjects(pushResponse.URL.absoluteString, @"http://mocked/pushed");
    XCTAssertEqual(pushResponse.statusCode, 200);
    XCTAssertEqualObjects([pushResponse.allHeaderFields valueForKey:@"PushHeader"], @"PushValue");
}

- (void)testSYNStreamWithStreamIDNonZeroPostsNotification
{
    SPDYMockURLProtocolClient __block *pushClient = nil;

    [[NSNotificationCenter defaultCenter] addObserverForName:SPDYPushRequestReceivedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        XCTAssertTrue([note.userInfo[@"request"] isKindOfClass:[NSURLRequest class]]);

        NSURLRequest *request = note.userInfo[@"request"];
        XCTAssertNotNil(request);
        XCTAssertEqualObjects(request.URL.absoluteString, @"http://mocked/pushed");

        pushClient = [self attachToPushRequest:request].client;
    }];

    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client. Notification posted at this point.
    [self mockServerSynStreamWithId:2 last:NO];
    XCTAssertNotNil(pushClient);
    XCTAssertFalse(pushClient.calledDidReceiveResponse);

    // Send HEADERS from server to client
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    XCTAssertTrue(pushClient.calledDidReceiveResponse);
    XCTAssertFalse(pushClient.calledDidLoadData);
    XCTAssertFalse(pushClient.calledDidFailWithError);
    XCTAssertFalse(pushClient.calledDidFinishLoading);
    
    NSHTTPURLResponse *pushResponse = pushClient.lastResponse;
    XCTAssertEqualObjects(pushResponse.URL.absoluteString, @"http://mocked/pushed");
    XCTAssertEqual(pushResponse.statusCode, 200);
    XCTAssertEqualObjects([pushResponse.allHeaderFields valueForKey:@"PushHeader"], @"PushValue");
}

- (void)testSYNStreamAfterAssociatedStreamClosesRespondsWithGoAway
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Close original
    [self mockServerDataFrameWithId:1 length:1 last:YES];

    // Send SYN_STREAM from server to client
    [self mockServerSynStreamWithId:2 last:NO];

    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)1);
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYGoAwayFrame class]]);
}

- (void)testSYNStreamsAndAssociatedStreamClosingDidCompleteWithMetadata
{
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    SPDYMockURLProtocolClient *pushClient2 = [self attachToPushRequestWithUrl:@"http://mocked/pushed"].client;

    // Send another SYN_STREAM from server to client
    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/pushed4"};
    [self mockServerSynStreamWithId:4 last:NO headers:headers];
    [self mockServerHeadersFrameForPushWithId:4 last:YES];
    SPDYMockURLProtocolClient *pushClient4 = [self attachToPushRequestWithUrl:@"http://mocked/pushed4"].client;

    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);
    XCTAssertTrue(_mockURLProtocolClient.calledDidReceiveResponse);
    XCTAssertFalse(_mockURLProtocolClient.calledDidFinishLoading);
    XCTAssertTrue(pushClient2.calledDidReceiveResponse);
    XCTAssertFalse(pushClient2.calledDidFinishLoading);
    XCTAssertTrue(pushClient4.calledDidReceiveResponse);
    XCTAssertTrue(pushClient4.calledDidFinishLoading);

    SPDYMetadata *metadata = [SPDYProtocol metadataForResponse:pushClient4.lastResponse];
    XCTAssertNotNil(metadata);

    // Close original
    [self mockServerDataFrameWithId:1 length:1 last:YES];
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);
    XCTAssertTrue(_mockURLProtocolClient.calledDidFinishLoading);
    XCTAssertFalse(pushClient2.calledDidFinishLoading);

    // Close push 1
    [self mockServerDataFrameWithId:2 length:2 last:YES];
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);
    XCTAssertTrue(pushClient2.calledDidFinishLoading);
}

#if 0

- (void)testSYNStreamClosesAfterHeadersMakesCompletionBlockCallback
{
    _mockExtendedDelegate.testSetsPushResponseDataDelegate = NO;

    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReply];

    // Send SYN_STREAM from server to client with 'last' bit set.
    [self mockServerSynStreamWithId:2 last:YES];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);  // for extended delegate
    XCTAssertNotNil(_mockExtendedDelegate.lastPushResponse);

    // Got the completion block callback indicating push response is done?
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse);
    XCTAssertEqual(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)0);
    XCTAssertNil(_mockPushResponseDataDelegate.lastCompletionError);
}

- (void)testSYNStreamClosesAfterDataWithDelayedExtendedCallbackMakesCompletionBlockCallback
{
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];

    // Send server SYN_STREAM, then send all data, before scheduling the run loop and
    // allowing the extended delegate callback to happen. Should be all ok.
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    [self mockServerDataFrameWithId:2 length:1 last:YES];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);

    XCTAssertNotNil(_mockExtendedDelegate.lastPushResponse);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse);
    XCTAssertEqual(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)1);
    XCTAssertNil(_mockPushResponseDataDelegate.lastCompletionError);
}

- (void)testSYNStreamWithDataMakesCompletionBlockCallback
{
    // Disable delegate and cache
    _mockExtendedDelegate.testSetsPushResponseDataDelegate = nil;
    _mockExtendedDelegate.testSetsPushResponseCache = nil;

    // Initial mainline SYN_STREAM, SYN_REPLY, server SYN_STREAM exchanges
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    XCTAssertNotNil(_mockExtendedDelegate.lastPushResponse);

    // Send DATA frame, verify callback made
    [self mockServerDataFrameWithId:2 length:100 last:YES];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);  // no errors
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushRequest);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionData);
    XCTAssertEqual(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)100);
    XCTAssertNil(_mockPushResponseDataDelegate.lastCompletionError);

    // Some sanity checks
    XCTAssertEqualObjects(_mockExtendedDelegate.lastPushResponse, _mockPushResponseDataDelegate.lastCompletionPushResponse);
    XCTAssertEqualObjects(_mockExtendedDelegate.lastPushRequest, _mockPushResponseDataDelegate.lastCompletionPushRequest);
}

 - (void)testSYNStreamWithChunkedDataMakesCompletionBlockCallback
 {
     // Disable delegate
     _mockExtendedDelegate.testSetsPushResponseDataDelegate = nil;
     [self mockPushResponseWithTwoDataFrames];

     XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse);
     XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushRequest);
     XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionData);
     XCTAssertEqual(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)201);
     XCTAssertNil(_mockPushResponseDataDelegate.lastCompletionError);
}

- (void)testSYNStreamClosedRespondsWithResetAndMakesCompletionBlockCallback
{
    // Initial mainline SYN_STREAM, SYN_REPLY, server SYN_STREAM exchanges
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);  // no errors

    // Cancel it
    // @@@ Uh, how to do this?
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);

    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)1);
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]]);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_CANCEL);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).streamId, (SPDYStreamId)2);

    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushRequest);
    XCTAssertNil(_mockPushResponseDataDelegate.lastCompletionData);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionError);
}

- (void)testSYNStreamWithChunkedDataMakesDataDelegateCallbacks
{
    // Disable completion block
    _mockExtendedDelegate.testSetsPushResponseCompletionBlock = nil;

    // Initial mainline SYN_STREAM, SYN_REPLY, server SYN_STREAM exchanges
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);  // no errors
    XCTAssertNotNil(_mockExtendedDelegate.lastPushResponse);

    // Send DATA frame, verify callback made
    [self mockServerDataFrameWithId:2 length:100 last:NO];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);  // no errors
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastRequest);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastData);
    XCTAssertEqual(_mockPushResponseDataDelegate.lastData.length, (NSUInteger)100);

    // Send last DATA frame
    [self mockServerDataFrameWithId:2 length:101 last:YES];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);  // no errors
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastRequest);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastData);
    XCTAssertEqual(_mockPushResponseDataDelegate.lastData.length, (NSUInteger)101);

    // Runloop may have scheduled the final didComplete callback before we could stop it. But
    // if not, wait for it.
    if (_mockPushResponseDataDelegate.lastMetadata == nil) {
        XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    }
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)0);  // no errors
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastMetadata);
    XCTAssertEqualObjects(_mockPushResponseDataDelegate.lastMetadata[SPDYMetadataVersionKey], @"3.1");
    XCTAssertEqualObjects(_mockPushResponseDataDelegate.lastMetadata[SPDYMetadataStreamIdKey], @"2");
    XCTAssertTrue([_mockPushResponseDataDelegate.lastMetadata[SPDYMetadataStreamRxBytesKey] integerValue] > 0);
    XCTAssertTrue([_mockPushResponseDataDelegate.lastMetadata[SPDYMetadataStreamTxBytesKey] integerValue] == 0);

    // Some sanity checks
    XCTAssertEqualObjects(_mockExtendedDelegate.lastPushRequest, _mockPushResponseDataDelegate.lastRequest);
    XCTAssertNil(_mockPushResponseDataDelegate.lastError);
}

- (void)testSYNStreamWithChunkedDataMakesDataDelegateAndCompletionBlockCallbacks
{
    // Disable caching
    _mockExtendedDelegate.testSetsPushResponseCache = nil;

    // Enable both completion block and delegate (default)
    [self mockPushResponseWithTwoDataFrames];

    // Verify last chunk received
    XCTAssertEqual(_mockPushResponseDataDelegate.lastData.length, (NSUInteger)101);

    // Ensure both happened
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse);
    XCTAssertNil(_mockPushResponseDataDelegate.lastCompletionError);
    XCTAssertEqual(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)201);
    XCTAssertNil(_mockPushResponseDataDelegate.lastError);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastMetadata);
}

- (void)testSYNStreamWithChunkedDataAndCustomCacheCachesResponse
{
    // Enabled caching only
    _mockExtendedDelegate.testSetsPushResponseDataDelegate = nil;
    _mockExtendedDelegate.testSetsPushResponseCompletionBlock = nil;
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];

    // Make a new request, don't use the NSURLRequest that got pushed to us
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];

    // Sanity check
    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    XCTAssertNil(response);

    [self mockPushResponseWithTwoDataFrames];

    // Ensure neither callback happened
    XCTAssertNil(_mockPushResponseDataDelegate.lastCompletionPushResponse);
    XCTAssertNil(_mockPushResponseDataDelegate.lastMetadata);

    response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    XCTAssertNotNil(response);
    XCTAssertEqual(response.data.length, (NSUInteger)201);
    XCTAssertEqualObjects(((NSHTTPURLResponse *)response.response).allHeaderFields[@"PushHeader"], @"PushValue");
}

- (void)testSYNStreamWithChunkedDataAndDelegateSetsNilCacheDoesNotCacheResponse
{
    // Enable nothing, but we still make the completion callback in didReceiveResponse
    _mockExtendedDelegate.testSetsPushResponseDataDelegate = nil;
    _mockExtendedDelegate.testSetsPushResponseCompletionBlock = nil;
    _mockExtendedDelegate.testSetsPushResponseCache = nil;

    // Sanity check
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    NSCachedURLResponse *response = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    XCTAssertNil(response);

    [self mockPushResponseWithTwoDataFrames];

    response = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    XCTAssertNil(response);
}

- (void)testSYNStreamWithChunkedDataAndDefaultCacheAndNoDelegateCachesResponse
{
    // Disable extended delegate
    [_URLRequest setExtendedDelegate:nil inRunLoop:nil forMode:nil];
    _protocolRequest = [[SPDYProtocol alloc] initWithRequest:_URLRequest cachedResponse:nil client:nil];

    // Sanity check
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    NSCachedURLResponse *response = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    XCTAssertNil(response);

    // No callbacks to wait for
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    [self mockServerDataFrameWithId:2 length:100 last:NO];
    [self mockServerDataFrameWithId:2 length:101 last:YES];

    response = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    XCTAssertNotNil(response);
    XCTAssertEqual(response.data.length, (NSUInteger)201);
    XCTAssertEqualObjects(((NSHTTPURLResponse *)response.response).allHeaderFields[@"PushHeader"], @"PushValue");
}

#endif

#pragma mark Headers-related push tests

- (void)testSYNStreamAndAHeadersFrameMergesValues
{
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    SPDYMockURLProtocolClient *pushClient = [self attachToPushRequestWithUrl:@"http://mocked/pushed"].client;

    XCTAssertTrue(pushClient.calledDidReceiveResponse);
    XCTAssertEqualObjects([pushClient.lastResponse.allHeaderFields valueForKey:@"PushHeader"], @"PushValue");
    XCTAssertEqualObjects([pushClient.lastResponse.allHeaderFields valueForKey:@"PushHeader2"], nil);

    // Send HEADERS frame
    NSDictionary *headers = @{@"PushHeader2":@"PushValue2"};
    [self mockServerHeadersFrameWithId:2 headers:headers last:NO];

    // TODO: no way to expose new headers to URLProtocolClient, can't verify presence of new header
    // except to say nothing crashed here.
}

- (void)testSYNStreamAndAHeadersFrameAfterDataIgnoresValues
{
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    SPDYMockURLProtocolClient *pushClient = [self attachToPushRequestWithUrl:@"http://mocked/pushed"].client;
    XCTAssertTrue(pushClient.calledDidReceiveResponse);

    // Send DATA frame
    [self mockServerDataFrameWithId:2 length:100 last:NO];
    XCTAssertTrue(pushClient.calledDidLoadData);

    // Send last HEADERS frame
    NSDictionary *headers = @{@"PushHeader2":@"PushValue2"};
    [self mockServerHeadersFrameWithId:2 headers:headers last:YES];

    // Ensure stream was closed and callback made
    XCTAssertTrue(pushClient.calledDidFinishLoading);

    // TODO: no way to expose new headers to URLProtocolClient, can't verify absence of new header.
}

#if 0

#pragma mark Cache-related tests

- (void)testSYNStreamWithChunkedDataDoesNotCacheWhenSuggestedResponseIsNil
{
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];
    _mockPushResponseDataDelegate.willCacheShouldReturnNil = YES;

    // Make a new request, don't use the NSURLRequest that got pushed to us
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];

    [self mockPushResponseWithTwoDataFrames];

    XCTAssertNotNil(_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse);

    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    XCTAssertNil(response);
}

- (void)testSYNStreamWithChunkedDataDoesCacheSuggestedResponse
{
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];

    // Make a new request, don't use the NSURLRequest that got pushed to us
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];

    [self mockPushResponseWithTwoDataFrames];

    XCTAssertNotNil(_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse);
    XCTAssertEqualObjects(_mockExtendedDelegate.lastPushResponse, _mockPushResponseDataDelegate.lastWillCacheSuggestedResponse.response);

    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    XCTAssertNotNil(response);
    XCTAssertEqual(response.data.length, (NSUInteger)201);
    XCTAssertEqualObjects(((NSHTTPURLResponse *)response.response).allHeaderFields[@"PushHeader"], @"PushValue");
}

- (void)testSYNStreamWithChunkedDataDoesCacheCustomSuggestedResponse
{
    //_mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];
    NSURLCache *URLCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024
                                                         diskCapacity:20 * 1024 * 1024
                                                             diskPath:nil];
    _mockExtendedDelegate.testSetsPushResponseCache = URLCache;

    [self mockPushResponseWithTwoDataFramesWithId:2];
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse);
    XCTAssertEqualObjects(_mockExtendedDelegate.lastPushResponse, _mockPushResponseDataDelegate.lastWillCacheSuggestedResponse.response);
    NSCachedURLResponse *lastCachedResponse = _mockPushResponseDataDelegate.lastWillCacheSuggestedResponse;

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    XCTAssertEqual(response.data.length, (NSUInteger)201);

    NSCachedURLResponse *newCachedResponse = [[NSCachedURLResponse alloc]
            initWithResponse:lastCachedResponse.response
                        data:[NSMutableData dataWithLength:1]   // mutated
                    userInfo:nil
               storagePolicy:_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse.storagePolicy];

    _mockPushResponseDataDelegate.willCacheReturnOverride = newCachedResponse;

    // Do it a again. First one was just to grab a response.
    [self mockPushResponseWithTwoDataFramesWithId:4];

    response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    XCTAssertEqual(response.data.length, (NSUInteger)1);
    XCTAssertEqualObjects(((NSHTTPURLResponse *)response.response).allHeaderFields[@"PushHeader"], @"PushValue");
}

- (void)testSYNStreamWithChunkedDataDoesNotCache500Response
{
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];

    NSDictionary *headers = @{@":status":@"500", @":version":@"http/1.1", @"PushHeader":@"PushValue"};
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameWithId:2 headers:headers last:NO];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);
    [self mockServerDataFrameWithId:2 length:1 last:YES];
    XCTAssertTrue([self waitForAnyCallbackOrFrame]);

    XCTAssertNotNil(_mockExtendedDelegate.lastPushResponse);
    XCTAssertEqual(_mockExtendedDelegate.lastPushResponse.statusCode, (NSInteger)500);
    XCTAssertNil(_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse);
    XCTAssertNotNil(_mockPushResponseDataDelegate.lastMetadata);
    XCTAssertNil(_mockPushResponseDataDelegate.lastError);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    XCTAssertNil(response);
}
#endif

@end
