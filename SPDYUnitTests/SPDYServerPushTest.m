//
//  SPDYServerPushTest.m
//  SPDY
//
//  Created by Klemen Verdnik on 6/10/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock.h>
#import <Expecta.h>
#import "SPDYOrigin.h"
#import "SPDYSession.h"
#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYFrame.h"
#import "SPDYFrameDecoder.h"
#import "SPDYFrameEncoder.h"
#import "SPDYFrameEncoderAccumulator.h"
#import "SPDYProtocol.h"
#import "SPDYStream.h"

@interface SPDYSession (Private)

@property (nonatomic, readonly) SPDYSocket *socket;

- (void)didReadPingFrame:(SPDYPingFrame *)pingFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)_sendPingResponse:(SPDYPingFrame *)pingFrame;
- (void)_sendSynStream:(SPDYStream *)stream streamId:(SPDYStreamId)streamId closeLocal:(bool)close;
- (void)_sendRstStream:(SPDYStreamStatus)status streamId:(SPDYStreamId)streamId;

@end

@implementation SPDYSession (Private)

- (SPDYSocket *)socket
{
    return [self valueForKey:@"_socket"];
}

- (NSMutableData *)inputBuffer
{
    return [self valueForKey:@"_inputBuffer"];
}

- (SPDYFrameDecoder *)frameDecoder
{
    return [self valueForKey:@"_frameDecoder"];
}

@end

@interface SPDYServerPushTest : XCTestCase
@end

@implementation SPDYServerPushTest

- (void)setUp
{

}

- (void)testReceivedPing
{
    // Swizzle the
    [SPDYSocket performSwizzling];
    
    // Initialize encoder (we're going to use it later)
    NSError *error;
    SPDYFrameEncoderAccumulator *accu = [[SPDYFrameEncoderAccumulator alloc] init];
    SPDYFrameEncoder *frameEncoder = [[SPDYFrameEncoder alloc] initWithDelegate:accu headerCompressionLevel:0];
    
    // Prepare a SPDYPingFrame frame
    SPDYPingFrame *pingFrame = [[SPDYPingFrame alloc] init];
    pingFrame.pingId = 0xA4;
    [frameEncoder encodePingFrame:pingFrame];

    // Initialize a SPDYSession
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"http://mocked" error:&error];
    SPDYSession *session = [[SPDYSession alloc] initWithOrigin:origin configuration:nil cellular:NO error:&error];
    id partialSessionMock = [OCMockObject partialMockForObject:session];
    [[[partialSessionMock expect] andForwardToRealObject] didReadPingFrame:[OCMArg any] frameDecoder:[OCMArg any]];
    [[[partialSessionMock expect] andForwardToRealObject] _sendPingResponse:[OCMArg any]];

    // Simulate server Tx
    [[partialSessionMock inputBuffer] appendData:accu.lastEncodedData];
    [[(SPDYSession *)partialSessionMock socket] performDelegateCall_socketDidReadData:accu.lastEncodedData withTag:0];
    
    [partialSessionMock verify];
}

@end
