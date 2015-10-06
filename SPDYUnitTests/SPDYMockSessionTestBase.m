//
//  SPDYMockSessionTestBase.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <XCTest/XCTest.h>
#import "SPDYMockFrameEncoderDelegate.h"
#import "SPDYMockFrameDecoderDelegate.h"
#import "SPDYMockSessionTestBase.h"
#import "SPDYMockURLProtocolClient.h"
#import "SPDYOrigin.h"
#import "SPDYSocket.h"
#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYStream.h"


@implementation SPDYMockStreamDelegate
{
    NSMutableData *_data;
}

- (id)init
{
    self = [super init];
    if (self) {
        _data = [NSMutableData new];
    }
    return self;
}

- (void)streamCanceled:(SPDYStream *)stream status:(SPDYStreamStatus)status;
{
    _calledStreamCanceled++;
    _lastStream = stream;
    _lastStatus = status;
}

- (void)streamClosed:(SPDYStream *)stream
{
    _calledStreamClosed++;
    _lastStream = stream;
}

- (void)streamDataAvailable:(SPDYStream *)stream
{
    _calledStreamDataAvailable++;
    _lastStream = stream;
    [_data appendData:[stream readData:10 error:nil]];
}

- (void)streamDataFinished:(SPDYStream *)stream
{
    _calledStreamDataFinished++;
    _lastStream = stream;
    _callback();
}

@end


@implementation SPDYMockSessionTestBase

- (void)setUp {
    [super setUp];
    [SPDYSocket performSwizzling:YES];
    _protocolList = [[NSMutableArray alloc] initWithCapacity:1];

    NSError *error = nil;
    _origin = [[SPDYOrigin alloc] initWithString:@"http://mocked" error:&error];
    _session = [[SPDYSession alloc] initWithOrigin:_origin
                                          delegate:nil
                                     configuration:[SPDYConfiguration defaultConfiguration]
                                          cellular:NO
                                             error:&error];
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];

    _testEncoderDelegate = [[SPDYMockFrameEncoderDelegate alloc] init];
    _testEncoder = [[SPDYFrameEncoder alloc] initWithDelegate:_testEncoderDelegate
                                       headerCompressionLevel:0];

    _mockDecoderDelegate = [[SPDYMockFrameDecoderDelegate alloc] init];
    _mockURLProtocolClient = [[SPDYMockURLProtocolClient alloc] init];
    _mockStreamDelegate = [[SPDYMockStreamDelegate alloc] init];
    socketMock_frameDecoder = [[SPDYFrameDecoder alloc] initWithDelegate:_mockDecoderDelegate];
}

- (void)tearDown
{
    [SPDYSocket performSwizzling:NO];
    [super tearDown];
}

- (SPDYProtocol *)createProtocol
{
    SPDYProtocol *protocolRequest = [[SPDYProtocol alloc] initWithRequest:_URLRequest cachedResponse:nil client:_mockURLProtocolClient];
    [_protocolList addObject:protocolRequest];
    return protocolRequest;
}

- (SPDYStream *)createStream
{
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol]];
    stream.delegate = _mockStreamDelegate;
    return stream;
}

- (void)makeSessionReadData:(NSData *)data
{
    // Simulate server Tx by preparing the encoded synStreamFrame
    // data inside _session's inputBuffer, and trigger a fake
    // delegate call, that notifies the _session about the newly received data.
    [[_session inputBuffer] setData:data];
    [[_session socket] performDelegateCall_socketDidReadData:data withTag:100];
}

- (void)makeSocketConnect
{
    [[_session socket] performDelegateCall_socketDidConnectToHost:@"testhost" port:1234];
}

- (SPDYStream *)mockSynStreamAndReplyWithId:(SPDYStreamId)streamId last:(bool)last
{
    if (streamId == 1) {
        [self makeSocketConnect];
    }

    // Issue a HTTP request towards the server, this will send the SYN_STREAM request and wait
    // for the SYN_REPLY. It will use stream-id of 1 since it's the first request.
    SPDYStream *stream = [self createStream];
    [_session openStream:stream];
    if (stream.request.HTTPBody) {
        XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)2);
        XCTAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYSynStreamFrame class]]);
        XCTAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYDataFrame class]]);
    } else {
        XCTAssertEqual(_mockDecoderDelegate.frameCount, (NSUInteger)1);
        XCTAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYSynStreamFrame class]]);
    }
    [_mockDecoderDelegate clear];

    [self mockServerSynReplyWithId:streamId last:last];

    // We should not expect any protocol errors to be issued from the client.
    XCTAssertNil(_mockDecoderDelegate.lastFrame);

    return stream;
}

- (void)mockServerSynReplyWithId:(SPDYStreamId)streamId last:(BOOL)last
{
    SPDYSynReplyFrame *synReplyFrame = [[SPDYSynReplyFrame alloc] init];
    synReplyFrame.headers = @{@":version":@"3.1", @":status":@"200"};
    synReplyFrame.streamId = streamId;
    synReplyFrame.last = last;

    XCTAssertTrue([_testEncoder encodeSynReplyFrame:synReplyFrame error:nil] > 0);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];
}

- (void)mockServerGoAwayWithLastGoodId:(SPDYStreamId)lastGoodStreamId statusCode:(SPDYSessionStatus)statusCode
{
    SPDYGoAwayFrame *frame = [[SPDYGoAwayFrame alloc] init];
    frame.lastGoodStreamId = lastGoodStreamId;
    frame.statusCode = statusCode;

    XCTAssertTrue([_testEncoder encodeGoAwayFrame:frame] > 0);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];
}

- (void)mockServerDataWithId:(SPDYStreamId)streamId data:(NSData *)data last:(BOOL)last
{
    SPDYDataFrame *frame = [[SPDYDataFrame alloc] init];
    frame.data = data;
    frame.streamId = streamId;
    frame.last = last;

    XCTAssertTrue([_testEncoder encodeDataFrame:frame] > 0);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];
}

- (void)mockServerSynStreamWithId:(uint32_t)streamId last:(BOOL)last
{
    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/pushed"};
    [self mockServerSynStreamWithId:streamId last:last headers:headers];
}

- (void)mockServerSynStreamWithId:(uint32_t )streamId last:(BOOL)last headers:(NSDictionary *)headers
{
    // Simulate a server Tx stream SYN_STREAM request (opening a push stream) that's associated
    // with the stream that the client created.
    SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = streamId;
    synStreamFrame.unidirectional = YES;
    synStreamFrame.last = last;
    synStreamFrame.headers = headers;
    synStreamFrame.associatedToStreamId = 1;

    XCTAssertTrue([_testEncoder encodeSynStreamFrame:synStreamFrame error:nil]);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];
}

- (void)mockServerHeadersFrameForPushWithId:(uint32_t)streamId last:(BOOL)last
{
    NSDictionary *headers = @{@":status":@"200", @":version":@"http/1.1", @"PushHeader":@"PushValue"};
    [self mockServerHeadersFrameWithId:streamId headers:headers last:last];
}

- (void)mockServerHeadersFrameWithId:(uint32_t )streamId headers:(NSDictionary *)headers last:(BOOL)last
{
    // Simulate a server Tx HEADERS_FRAME.
    SPDYHeadersFrame *headersFrame = [[SPDYHeadersFrame alloc] init];
    headersFrame.streamId = streamId;
    headersFrame.headers = headers;
    headersFrame.last = last;

    XCTAssertTrue([_testEncoder encodeHeadersFrame:headersFrame error:nil]);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];
}

- (void)mockServerDataFrameWithId:(uint32_t )streamId length:(NSUInteger)length last:(BOOL)last
{
    // Simulate a server Tx stream DATA_FRAME.
    SPDYDataFrame *dataFrame = [[SPDYDataFrame alloc] init];
    dataFrame.streamId = streamId;
    dataFrame.last = last;
    dataFrame.data = [NSMutableData dataWithLength:length];

    XCTAssertTrue([_testEncoder encodeDataFrame:dataFrame]);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];
}

// Helper method for many test cases
- (void)mockPushResponseWithTwoDataFrames
{
    [self mockPushResponseWithTwoDataFramesWithId:2];
}

- (void)mockPushResponseWithTwoDataFramesWithId:(SPDYStreamId)streamId
{
    // Exchange initial SYN_STREAM and SYN_REPLY and server SYN_STREAM
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynStreamWithId:streamId last:NO];

    // Send DATA frames
    [self mockServerDataFrameWithId:streamId length:100 last:NO];
    [self mockServerDataFrameWithId:streamId length:101 last:YES];
}

@end
