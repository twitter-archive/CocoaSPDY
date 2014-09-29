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

#import <SenTestingKit/SenTestingKit.h>
#import <Foundation/Foundation.h>
#import "SPDYOrigin.h"
#import "SPDYSession.h"
#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYFrame.h"
#import "SPDYMockFrameEncoderDelegate.h"
#import "SPDYProtocol.h"
#import "SPDYMockFrameDecoderDelegate.h"
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYStream.h"

@interface SPDYSessionTest : SenTestCase <SPDYExtendedDelegate>
@end

@implementation SPDYSessionTest
{
    // Most of these objects need to be retained for the life of the test. Hence the macro. I don't
    // want to use instance variables and setUp / tearDown.
    // Note on frameEncoder:
    // Used locally for encoding frames. Whatever gets encoded manually in the frameEncoder
    // here *must* get decoded by the session, else the zlib library gets out of sync and you'll
    // get Z_DATA_ERROR errors ("incorrect header check").
    // Note on URLRequest and protocolRequest:
    // We *must* maintain references to these for the whole test.
    SPDYOrigin *_origin;
    SPDYSession *_session;
    NSMutableURLRequest *_URLRequest;
    SPDYProtocol *_protocolRequest;
    SPDYFrameEncoder *_testEncoder;
    SPDYMockFrameEncoderDelegate *_testEncoderDelegate;
    SPDYMockFrameDecoderDelegate *_mockDecoderDelegate;

    // From SPDYExtendedDelegate callbacks. Reset every test.
    NSDictionary *_lastMetadata;

}

#pragma mark SPDYExtendedDelegate overrides

- (void)requestDidCompleteWithMetadata:(NSDictionary *)metadata
{
    _lastMetadata = metadata;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

#pragma mark Test Helpers

- (void)setUp {
    [super setUp];
    [SPDYSocket performSwizzling:YES];
    _lastMetadata = nil;

    NSError *error = nil;
    _origin = [[SPDYOrigin alloc] initWithString:@"http://mocked" error:&error];
    _session = [[SPDYSession alloc] initWithOrigin:_origin
                                          delegate:nil
                                     configuration:nil
                                          cellular:NO
                                             error:&error];
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    [_URLRequest setExtendedDelegate:self inRunLoop:nil forMode:nil];
    _protocolRequest = [[SPDYProtocol alloc] initWithRequest:_URLRequest cachedResponse:nil client:nil];

    _testEncoderDelegate = [[SPDYMockFrameEncoderDelegate alloc] init];
    _testEncoder = [[SPDYFrameEncoder alloc] initWithDelegate:_testEncoderDelegate
                                       headerCompressionLevel:0];

    _mockDecoderDelegate = [[SPDYMockFrameDecoderDelegate alloc] init];
    socketMock_frameDecoder = [[SPDYFrameDecoder alloc] initWithDelegate:_mockDecoderDelegate];
}

- (void)tearDown
{
    [SPDYSocket performSwizzling:NO];
    [super tearDown];
}

- (void)makeSessionReadData:(NSData *)data
{
    // Simulate server Tx by preparing the encoded synStreamFrame
    // data inside _session's inputBuffer, and trigger a fake
    // delegate call, that notifies the _session about the newly received data.
    [[_session inputBuffer] setData:data];
    [[_session socket] performDelegateCall_socketDidReadData:data withTag:100];
}

- (void)waitForExtendedCallbackOrError
{
    // Wait for callback via SPDYExtendedDelegate or a RST_STREAM or GOAWAY to be sent.
    // Errors are processed synchronously, but callbacks are async. They will stop the runloop.
    if (_mockDecoderDelegate.lastFrame != nil) {
        return;
    } else {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, NO);
    }
}

- (void)mockSynStreamAndReplyWithId:(SPDYStreamId)streamId last:(bool)last
{
    // Prepare the synReplyFrame. The SYN_STREAM will use stream-id 1 since it is the first
    // request sent by the client. We can't control that without mocking, so we have to hard-code
    // the SYN_REPLY stream id.
    SPDYSynReplyFrame *synReplyFrame = [[SPDYSynReplyFrame alloc] init];
    synReplyFrame.headers = @{@":version":@"3.1", @":status":@"200"};
    synReplyFrame.streamId = streamId;
    synReplyFrame.last = last;

    // 1.) Issue a HTTP request towards the server, this will send the SYN_STREAM request and wait
    // for the SYN_REPLY. It will use stream-id of 1 since it's the first request.
    [_session openStream:[[SPDYStream alloc] initWithProtocol:_protocolRequest]];
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]], nil);
    [_mockDecoderDelegate clear];

    // 2.) Simulate a server Tx stream SYN reply
    STAssertTrue([_testEncoder encodeSynReplyFrame:synReplyFrame error:nil] > 0, nil);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];

    // 2.1) We should not expect any protocol errors to be issued from the client.
    STAssertNil(_mockDecoderDelegate.lastFrame, nil);
}

#pragma mark Tests

- (void)testCloseSessionWithMultipleStreams
{
    // Exchange initial SYN_STREAM and SYN_REPLY for 2 streams then close the session. This
    // causes a GOAWAY and RST_STREAMs to be sent, via the "_closeWithStatus" method. That's
    // what we're testing.
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockSynStreamAndReplyWithId:3 last:NO];
    [_session close];

    [self waitForExtendedCallbackOrError];

    STAssertNotNil(_mockDecoderDelegate.lastFrame, nil);
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]], nil);

    // Note: we should probably check if metadata is present, but we don't actually receive the
    // "didFailWithError" callbacks from NSURLConnectionDataDelegate, since we don't set up
    // anything related to the URL loading system. So we can't see it.
    // Need OCMock to do that.
}

- (void)testReceivedMetadataForSingleShortRequest
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:YES];

    [self waitForExtendedCallbackOrError];

    STAssertNil(_mockDecoderDelegate.lastFrame, nil);
    STAssertNotNil(_lastMetadata, nil);
    STAssertEqualObjects(_lastMetadata[SPDYMetadataVersionKey], @"3.1", nil);
    STAssertEqualObjects(_lastMetadata[SPDYMetadataStreamIdKey], @"1", nil);
    STAssertTrue([_lastMetadata[SPDYMetadataStreamRxBytesKey] integerValue] > 0, nil);
    STAssertTrue([_lastMetadata[SPDYMetadataStreamTxBytesKey] integerValue] > 0, nil);
}

@end
