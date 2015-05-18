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

#pragma mark Simple push callback tests

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

@end
