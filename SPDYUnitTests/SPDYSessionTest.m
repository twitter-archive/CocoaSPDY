//
//  SPDYSessionTest.m
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
#import <Foundation/Foundation.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYFrame.h"
#import "SPDYMockFrameEncoderDelegate.h"
#import "SPDYMockFrameDecoderDelegate.h"
#import "SPDYMockSessionTestBase.h"
#import "SPDYMockURLProtocolClient.h"
#import "SPDYOrigin.h"
#import "SPDYSession.h"
#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYStopwatch.h"
#import "SPDYStream.h"

@interface SPDYSessionTest : SPDYMockSessionTestBase
@end

@implementation SPDYSessionTest

- (void)testCloseSessionWithMultipleStreams
{
    // Exchange initial SYN_STREAM and SYN_REPLY for 2 streams then close the session. This
    // causes a GOAWAY and RST_STREAMs to be sent, via the "_closeWithStatus" method. That's
    // what we're testing.
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockSynStreamAndReplyWithId:3 last:YES];
    [self mockSynStreamAndReplyWithId:5 last:NO];
    [_session close];

    // Was a RST_STREAM sent?
    XCTAssertNotNil(_mockDecoderDelegate.lastFrame);
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]]);

    // Was connection:didFailWithError called?
    XCTAssertTrue(_mockURLProtocolClient.calledDidFailWithError);
    XCTAssertNotNil(_mockURLProtocolClient.lastError);

    // Was metadata populated for the error?
    SPDYMetadata *metadata = [SPDYProtocol metadataForError:_mockURLProtocolClient.lastError];
    XCTAssertEqualObjects(metadata.version, @"3.1");
    XCTAssertEqual(metadata.streamId, (NSUInteger)5);
}

- (void)testReceivedMetadataForSingleShortRequest
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:YES];

    XCTAssertNil(_mockDecoderDelegate.lastFrame);
    XCTAssertTrue(_mockURLProtocolClient.calledDidFinishLoading);
    XCTAssertNotNil(_mockURLProtocolClient.lastResponse);

    SPDYMetadata *metadata = [SPDYProtocol metadataForResponse:_mockURLProtocolClient.lastResponse];
    XCTAssertEqualObjects(metadata.version, @"3.1");
    XCTAssertEqual(metadata.streamId, (NSUInteger)1);
    XCTAssertTrue(metadata.rxBytes > 0);
    XCTAssertTrue(metadata.txBytes > 0);
    XCTAssertEqual(metadata.rxBodyBytes, (NSUInteger)0);
    XCTAssertEqual(metadata.txBodyBytes, (NSUInteger)0);
}

- (void)testReceivedMetadataForSingleShortRequestWithBody
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://mocked/init"]];
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.HTTPBody = [[NSMutableData alloc] initWithLength:1000];
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerDataWithId:1 data:[[NSMutableData alloc] initWithLength:2000] last:YES];

    XCTAssertNil(_mockDecoderDelegate.lastFrame);
    XCTAssertTrue(_mockURLProtocolClient.calledDidFinishLoading);
    XCTAssertNotNil(_mockURLProtocolClient.lastResponse);

    SPDYMetadata *metadata = [SPDYProtocol metadataForResponse:_mockURLProtocolClient.lastResponse];
    XCTAssertEqualObjects(metadata.version, @"3.1");
    XCTAssertEqual(metadata.streamId, (NSUInteger)1);
    XCTAssertTrue(metadata.rxBytes > 2008);
    XCTAssertTrue(metadata.txBytes > 1008);
    XCTAssertEqual(metadata.rxBodyBytes, (NSUInteger)2008);
    XCTAssertEqual(metadata.txBodyBytes, (NSUInteger)1008);
}

- (void)testReceivedStreamTimingsMetadataForSingleShortRequest
{
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil];
    [_session openStream:stream];
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]]);
    [_mockDecoderDelegate clear];

    [SPDYStopwatch sleep:1.0];
    [self mockServerSynReplyWithId:1 last:NO];

    [SPDYStopwatch sleep:1.0];
    NSMutableData *data = [NSMutableData dataWithLength:1];
    [self mockServerDataWithId:1 data:data last:NO];
    [SPDYStopwatch sleep:1.0];
    [self mockServerDataWithId:1 data:data last:YES];

    // These fields aren't yet exposed externally; when they are, this code should change.
    SPDYMetadata *metadata = stream.metadata;
    XCTAssertEqualObjects(metadata.version, @"3.1");
    XCTAssertTrue(metadata.timeSessionConnected > 0);
    XCTAssertTrue(metadata.timeStreamCreated >= metadata.timeSessionConnected);
    XCTAssertTrue(metadata.timeStreamRequestStarted >= metadata.timeStreamCreated);
    XCTAssertTrue(metadata.timeStreamRequestLastHeader >= metadata.timeStreamRequestStarted);
    XCTAssertTrue(metadata.timeStreamRequestFirstData == 0);
    XCTAssertTrue(metadata.timeStreamRequestLastData == 0);
    XCTAssertTrue(metadata.timeStreamRequestEnded >= metadata.timeStreamRequestStarted);

    XCTAssertTrue(metadata.timeStreamResponseStarted >= metadata.timeStreamRequestEnded + 1.0);
    XCTAssertTrue(metadata.timeStreamResponseLastHeader >= metadata.timeStreamResponseStarted);
    XCTAssertTrue(metadata.timeStreamResponseFirstData >= metadata.timeStreamResponseLastHeader + 1.0);
    XCTAssertTrue(metadata.timeStreamResponseLastData >= metadata.timeStreamResponseFirstData + 1.0);
    XCTAssertTrue(metadata.timeStreamResponseEnded >= metadata.timeStreamResponseStarted + 2.0);
    XCTAssertTrue(metadata.timeStreamClosed >= metadata.timeStreamResponseEnded);
}

- (void)testReceiveGOAWAYAfterStreamsClosedDoesCloseSession
{
    [self mockSynStreamAndReplyWithId:1 last:YES];
    [self mockSynStreamAndReplyWithId:3 last:YES];
    [self mockSynStreamAndReplyWithId:5 last:YES];
    [self mockServerGoAwayWithLastGoodId:5 statusCode:SPDY_SESSION_OK];
    XCTAssertEqual(_session.load, (NSUInteger)0);
    XCTAssertFalse(_session.isOpen);
}

- (void)testReceiveGOAWAYWithOpenStreamsDoesNotCloseSession
{
    [self mockSynStreamAndReplyWithId:1 last:YES];
    [self mockSynStreamAndReplyWithId:3 last:NO];
    [self mockSynStreamAndReplyWithId:5 last:NO];
    [self mockServerGoAwayWithLastGoodId:5 statusCode:SPDY_SESSION_OK];
    XCTAssertEqual(_session.load, (NSUInteger)2);
    XCTAssertFalse(_session.isOpen);
}

- (void)testReceiveGOAWAYWithInFlightStreamsDoesCloseStreams
{
    [self mockSynStreamAndReplyWithId:1 last:YES];
    [self mockSynStreamAndReplyWithId:3 last:NO];
    [self mockSynStreamAndReplyWithId:5 last:NO];
    [self mockServerGoAwayWithLastGoodId:1 statusCode:SPDY_SESSION_OK];
    XCTAssertEqual(_session.load, (NSUInteger)0);
    XCTAssertFalse(_session.isOpen);
}

- (void)testReceiveGOAWAYWithInFlightStreamDoesResetStreams
{
    [self mockSynStreamAndReplyWithId:1 last:YES];

    // Send two SYN_STREAMs only, no reply
    [_session openStream:[[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil]];
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]]);
    [_mockDecoderDelegate clear];

    [_session openStream:[[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil]];
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]]);
    [_mockDecoderDelegate clear];

    [self mockServerGoAwayWithLastGoodId:1 statusCode:SPDY_SESSION_OK];
    XCTAssertEqual(_session.load, (NSUInteger)0);
    XCTAssertFalse(_session.isOpen);

    // TODO: verify these streams were sent back to the session manager
}

- (void)testSendDATABufferRemainsValidAfterRequestIsDone
{
    NSMutableData * __weak weakData = nil;
    @autoreleasepool {
        @autoreleasepool {
            NSMutableData *data = [NSMutableData dataWithLength:16];
            ((uint8_t *)data.bytes)[0] = 1;
            weakData = data;
            NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
            urlRequest.HTTPBody = data;
            SPDYProtocol *protocolRequest = [[SPDYProtocol alloc] initWithRequest:urlRequest cachedResponse:nil client:_mockURLProtocolClient];

            // Copy of:
            // [self mockSynStreamAndReplyWithId:1 last:NO];

            // Prepare the synReplyFrame. The SYN_STREAM will use stream-id 1 since it is the first
            // request sent by the client. We can't control that without mocking, so we have to hard-code
            // the SYN_REPLY stream id.
            SPDYSynReplyFrame *synReplyFrame = [[SPDYSynReplyFrame alloc] init];
            synReplyFrame.headers = @{@":version" : @"3.1", @":status" : @"200"};
            synReplyFrame.streamId = 1;
            synReplyFrame.last = YES;

            // 1.) Issue a HTTP request towards the server, this will send the SYN_STREAM request and wait
            // for the SYN_REPLY. It will use stream-id of 1 since it's the first request.
            [_session openStream:[[SPDYStream alloc] initWithProtocol:protocolRequest pushStreamManager:nil]];
            XCTAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYSynStreamFrame class]]);
            XCTAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYDataFrame class]]);
            XCTAssertTrue(((SPDYDataFrame *)_mockDecoderDelegate.framesReceived[1]).last);
            XCTAssertNotNil(socketMock_lastWriteOp);
            XCTAssertEqual(socketMock_lastWriteOp->_buffer.length, data.length);
            [_mockDecoderDelegate clear];

            // 1 active stream
            XCTAssertEqual(_session.load, (NSUInteger)1);

            // 2.) Simulate a server Tx stream SYN reply
            XCTAssertTrue([_testEncoder encodeSynReplyFrame:synReplyFrame error:nil] > 0);
            [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
            [_testEncoderDelegate clear];

            // 2.1) We should not expect any protocol errors to be issued from the client.
            XCTAssertNil(_mockDecoderDelegate.lastFrame);

            // Ensure completion callback (our custom one) was called to verify request is actually
            // finished.
            XCTAssertTrue(_mockURLProtocolClient.calledDidFinishLoading);

            // At this point, socketMock_lastWriteOp is holding a pointer to our data. That simulates
            // what happens deep inside SPDYSocket if, for instance, other operations are queued
            // in front of ours or the full buffer cannot be written to the stream just yet.
            // Eventually the operation will be released, but we want to test the case where it
            // is still in progress and the stream goes away.

            // No more active streams
            XCTAssertEqual(_session.load, (NSUInteger)0);

            // Need to test that the write op's buffered data isn't our data pointer, since it is
            // about to go away. I'd like to do that without crashing the unit test, so we'll
            // mutate the original buffer and verify our hypothesis after releasing the request.
            // Lots of sanity checks here on out.
            XCTAssertTrue(((uint8_t *)socketMock_lastWriteOp->_buffer.bytes)[0] == 1);
            ((uint8_t *)data.bytes)[0] = 2;
            XCTAssertTrue(((uint8_t *)weakData.bytes)[0] == 2);
        }  // <<< this releases the request

        XCTAssertNotNil(socketMock_lastWriteOp);  // sanity
        if (weakData == nil) {
            // Buffer expected to have been copied since original is released. Data should be
            // original non-mutated value.
            XCTAssertTrue(((uint8_t *)socketMock_lastWriteOp->_buffer.bytes)[0] == 1,
                    @"socket still references original buffer which has been released");
        } else {
            // Buffer expected to have been retained by the socket since the original has not been
            // released yet. It would be dumb to retain it but still make a data copy, so let's
            // verify the socket's buffer still points to the original which was mutated.
            XCTAssertTrue(((uint8_t *)socketMock_lastWriteOp->_buffer.bytes)[0] == 2,
                    @"socket should still point to the original buffer which has not been released yet");
        }

        // Dequeue
        socketMock_lastWriteOp = nil;
    }  // <<< this releases the "queued" write

    // And verify original buffer is now gone
    XCTAssertNil(weakData);
}

- (void)testCancelStreamDoesSendResetAndCloseStream
{
    SPDYStream * __weak weakStream = nil;
    @autoreleasepool {
        SPDYStream *stream = [self mockSynStreamAndReplyWithId:1 last:NO];
        weakStream = stream;
        [stream cancel];

        XCTAssertNotNil(_mockDecoderDelegate.lastFrame);
        XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]]);
        XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_CANCEL);
        XCTAssertTrue(_session.isOpen);
        XCTAssertEqual(_session.load, (NSUInteger)0);
    }
    // Ensure stream was released as well
    XCTAssertNil(weakStream);
}

- (void)testReceiveDATABeforeSYNREPLYDoesResetAndCloseStream
{
    NSMutableData *data = [NSMutableData dataWithLength:1];

    // Send a SYN_STREAM, no reply
    [_session openStream:[[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil]];
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]]);
    [_mockDecoderDelegate clear];

    // Reply with DATA
    [self mockServerDataWithId:1 data:data last:NO];

    // Ensure RST_STREAM was sent
    XCTAssertNotNil(_mockDecoderDelegate.lastFrame);
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]]);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_PROTOCOL_ERROR);
    XCTAssertTrue(_session.isOpen);
    XCTAssertEqual(_session.load, (NSUInteger)0);
}

- (void)testReceiveMultipleSYNREPLYDoesResetAndCloseStream
{
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynReplyWithId:1 last:NO];

    // Ensure RST_STREAM was sent
    XCTAssertNotNil(_mockDecoderDelegate.lastFrame);
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]]);
    XCTAssertEqual(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_STREAM_IN_USE);
    XCTAssertTrue(_session.isOpen);
    XCTAssertEqual(_session.load, (NSUInteger)0);
}

- (void)testInitWithTcpNodelayDoesSendPING
{
    NSError *error = nil;
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.enableTCPNoDelay = YES;
    _session = [[SPDYSession alloc] initWithOrigin:_origin
                                          delegate:nil
                                     configuration:configuration
                                          cellular:NO
                                             error:&error];

    XCTAssertFalse(_session.isEstablished);
    XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYPingFrame class]]);
    XCTAssertEqual(((SPDYPingFrame *)_mockDecoderDelegate.lastFrame).pingId, (SPDYPingId)1);

    // Reply with response
    SPDYPingFrame *pingFrame = [[SPDYPingFrame alloc] init];
    pingFrame.pingId = 1;  // server-initiated is even

    XCTAssertTrue([_testEncoder encodePingFrame:pingFrame] > 0);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];
    XCTAssertTrue(_session.isEstablished);
}

- (void)testServerPING
{
    SPDYPingFrame *pingFrame = [[SPDYPingFrame alloc] init];
    pingFrame.pingId = 2;  // server-initiated is even

    XCTAssertTrue([_testEncoder encodePingFrame:pingFrame] > 0);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];

    // Verify ping response sent
    XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)1);
    XCTAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYPingFrame class]]);
    XCTAssertEqual(((SPDYPingFrame *)_mockDecoderDelegate.framesReceived[0]).pingId, (SPDYPingId)2);
}

- (void)testMergeHeadersWithLocationAnd200DoesRedirect
{
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://mocked/init"]];
    _URLRequest.SPDYPriority = 3;
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.SPDYBodyFile = @"bodyfile.txt";
    _URLRequest.SPDYDeferrableInterval = 1.0;
    [_URLRequest setValue:@"50" forHTTPHeaderField:@"content-length"];

    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"https", @":host":@"mocked", @":path":@"/init",
            @":status":@"200", @":version":@"http/1.1", @"Header1":@"Value1",
            @"location":@"/newpath"};
    NSURL *redirectUrl = [NSURL URLWithString:@"https://mocked/newpath"];

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    XCTAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest);

    NSURLRequest *redirectRequest = _mockURLProtocolClient.lastRedirectedRequest;
    XCTAssertEqualObjects(redirectRequest.URL.absoluteString, redirectUrl.absoluteString);
    XCTAssertEqualObjects(redirectRequest.URL, redirectUrl);
    XCTAssertEqual(redirectRequest.SPDYPriority, (NSUInteger)3);
    XCTAssertEqualObjects(redirectRequest.HTTPMethod, @"POST");
    XCTAssertEqualObjects(redirectRequest.SPDYBodyFile, @"bodyfile.txt");
    XCTAssertEqual(redirectRequest.SPDYDeferrableInterval, 1.0);
    XCTAssertEqualObjects(redirectRequest.allSPDYHeaderFields[@"content-length"], @"50");
    XCTAssertNotNil(redirectRequest.allSPDYHeaderFields[@"content-type"]);

    XCTAssertEqualObjects(((NSHTTPURLResponse *)_mockURLProtocolClient.lastRedirectResponse).allHeaderFields[@"Header1"], @"Value1");
}

- (void)testMergeHeadersWithLocationAnd302DoesRedirectToGET
{
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.SPDYBodyFile = @"bodyfile.txt";
    [_URLRequest setValue:@"50" forHTTPHeaderField:@"content-length"];

    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
            @":status":@"302", @":version":@"http/1.1", @"Header1":@"Value1",
            @"location":@"https://mocked2/newpath"};
    NSURL *redirectUrl = [NSURL URLWithString:@"https://mocked2/newpath"];

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    XCTAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest);

    NSURLRequest *redirectRequest = _mockURLProtocolClient.lastRedirectedRequest;
    XCTAssertEqualObjects(redirectRequest.URL.absoluteString, redirectUrl.absoluteString);
    XCTAssertEqualObjects(redirectRequest.URL, redirectUrl);
    XCTAssertEqualObjects(redirectRequest.HTTPMethod, @"GET", @"expect GET after 302");  // 302 generally means GET
    XCTAssertNil(redirectRequest.SPDYBodyFile);
    XCTAssertNil(redirectRequest.HTTPBodyStream);
    XCTAssertNil(redirectRequest.allSPDYHeaderFields[@"content-length"]);
    XCTAssertNil(redirectRequest.allSPDYHeaderFields[@"content-type"]);
}

- (void)testMergeHeadersWithLocationAnd303DoesRedirectToGET
{
    NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:@"foo"];
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://mocked/init"]];
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.HTTPBodyStream = inputStream;  // test stream this time
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"https", @":host":@"mocked", @":path":@"/init",
            @":status":@"303", @":version":@"http/1.1", @"Header1":@"Value1",
            @"location":@"/newpath?param=value&foo=1"};
    NSURL *redirectUrl = [NSURL URLWithString:@"https://mocked/newpath?param=value&foo=1"];

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    XCTAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest);

    NSURLRequest *redirectRequest = _mockURLProtocolClient.lastRedirectedRequest;
    XCTAssertEqualObjects(redirectRequest.URL.absoluteString, redirectUrl.absoluteString);
    XCTAssertEqualObjects(redirectRequest.URL, redirectUrl);
    XCTAssertEqualObjects(redirectRequest.HTTPMethod, @"GET", @"expect GET after 303");  // 303 means GET
    XCTAssertNil(redirectRequest.SPDYBodyFile);
    XCTAssertNil(redirectRequest.HTTPBodyStream);
    XCTAssertNil(redirectRequest.allSPDYHeaderFields[@"content-length"]);
    XCTAssertNil(redirectRequest.allSPDYHeaderFields[@"content-type"]);
}

- (void)testNetworkChangesWhenSocketConnectsDoesUpdateActiveStreamMetadata
{
    // Queue stream to session (set to WIFI)
    SPDYStream *stream = [self mockSynStreamAndReplyWithId:1 last:NO];
    XCTAssertTrue(_session.isOpen);
    XCTAssertFalse(stream.closed);

    SPDYMetadata *metadata = [stream metadata];
    XCTAssertFalse(metadata.cellular);

    // Then force socket connection on different network.
    [_session.socket setCellular:YES];
    [_session.socket performDelegateCall_socketDidConnectToHost:_origin.host port:_origin.port];

    XCTAssertTrue(_session.isOpen);
    XCTAssertFalse(stream.closed);

    metadata = [stream metadata];
    XCTAssertTrue(metadata.cellular);
}

@end

