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

- (void)testSYNStreamWithStreamIDZeroRespondsWithError
{
    // Swizzle the
    [SPDYSocket performSwizzling];
    
    // Initialize encoder (we're going to use it later)
    NSError *error;
    SPDYFrameEncoderAccumulator *accu = [[SPDYFrameEncoderAccumulator alloc] init];
    SPDYFrameEncoder *frameEncoder = [[SPDYFrameEncoder alloc] initWithDelegate:accu headerCompressionLevel:0];
    
    // Prepare the SPDYSynStreamFrame
    __block SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = 0; // This is illegal, and it should fail!
    synStreamFrame.unidirectional = YES;
    synStreamFrame.headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"init"};
    
    // Prepare the synReplyFrame
    SPDYSynReplyFrame *synReplyFrame = [[SPDYSynReplyFrame alloc] init];
    synReplyFrame.headers = @{@":version":@"3.1", @":status":@"200"};

    // Make a fake URL request
    NSURLRequest *URLRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    SPDYProtocol *protocolRequest = [[SPDYProtocol alloc] initWithRequest:URLRequest cachedResponse:nil client:nil];
    
    // Initialize a SPDYSession
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"http://mocked" error:&error];
    SPDYSession *session = [[SPDYSession alloc] initWithOrigin:origin configuration:nil cellular:NO error:&error];
    
    __autoreleasing id partialSessionMock = [OCMockObject partialMockForObject:session];

    // Catch the syn stream frame the client's about to send,
    // and grab the stream ID from it.
    [[[[[partialSessionMock expect] ignoringNonObjectArgs] andForwardToRealObject] andDo:^(NSInvocation *inv) {
        [inv retainArguments];
        __unsafe_unretained SPDYSynStreamFrame *clientSentSynStreamFrame;
        [inv getArgument:&clientSentSynStreamFrame atIndex:2];
        
        // Set the associated stream id in the syn stream frame
        // we want to send from the server.
        synStreamFrame.associatedToStreamId = clientSentSynStreamFrame.streamId;;
        synReplyFrame.streamId = clientSentSynStreamFrame.streamId;
    }] _sendSynStream:[OCMArg any] streamId:0xf00ba4 closeLocal:[OCMArg anyPointer]];
  
    // 1.) Issue a HTTP request towards the server, this will
    //     send the SYN_STREAM request and wait for the SYN_REPLY.
    [partialSessionMock issueRequest:protocolRequest];

    // 2.) Simulate a server Tx stream SYN reply
    {
        // At this point, our synStreamFrame is populated with the
        // newly assigned streamID. We can encode it now.
        [frameEncoder encodeSynReplyFrame:synReplyFrame];

        // Simulate server Tx by preparing the encoded synStreamFrame
        // data inside session's inputBuffer, and trigger a fake
        // delegate call, that notifies the session about the newly received data.
        [[partialSessionMock inputBuffer] setData:accu.lastEncodedData];
        [[(SPDYSession *)partialSessionMock socket] performDelegateCall_socketDidReadData:accu.lastEncodedData withTag:100];
    };
    
    // 2.1) We are expecting a protocol error, since the streamID
    //      received in SYN_REPLY is 0.
    [[[[partialSessionMock expect] ignoringNonObjectArgs] andForwardToRealObject] _sendRstStream:0xf00ba4 streamId:0xf00ba4];

    // 3.) Simulate a server Tx stream SYN request (opening a push stream)
    //     that's associated with the stream that the client created.
    {
        [frameEncoder encodeSynStreamFrame:synStreamFrame];
        [[partialSessionMock inputBuffer] setData:accu.lastEncodedData];
        [[(SPDYSession *)partialSessionMock socket] performDelegateCall_socketDidReadData:accu.lastEncodedData withTag:101];
    };
    
    [partialSessionMock verify];
}

- (void)testSYNStreamWithStreamIDNonZeroSucceeds
{
    // Swizzle the
    [SPDYSocket performSwizzling];
    
    // Initialize encoder (we're going to use it later)
    NSError *error;
    SPDYFrameEncoderAccumulator *accu = [[SPDYFrameEncoderAccumulator alloc] init];
    SPDYFrameEncoder *frameEncoder = [[SPDYFrameEncoder alloc] initWithDelegate:accu headerCompressionLevel:0];
    
    // Prepare the SPDYSynStreamFrame
    __block SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = 100;
    synStreamFrame.unidirectional = YES;
    synStreamFrame.headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"init"};
    
    // Prepare the synReplyFrame
    SPDYSynReplyFrame *synReplyFrame = [[SPDYSynReplyFrame alloc] init];
    synReplyFrame.headers = @{@":version":@"3.1", @":status":@"200"};
    
    // Make a fake URL request
    NSURLRequest *URLRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    SPDYProtocol *protocolRequest = [[SPDYProtocol alloc] initWithRequest:URLRequest cachedResponse:nil client:nil];
    
    // Initialize a SPDYSession
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"http://mocked" error:&error];
    SPDYSession *session = [[SPDYSession alloc] initWithOrigin:origin configuration:nil cellular:NO error:&error];
    
    __autoreleasing id partialSessionMock = [OCMockObject partialMockForObject:session];
    
    // Catch the syn stream frame the client's about to send,
    // and grab the stream ID from it.
    [[[[[partialSessionMock expect] ignoringNonObjectArgs] andForwardToRealObject] andDo:^(NSInvocation *inv) {
        [inv retainArguments];
        __unsafe_unretained SPDYSynStreamFrame *clientSentSynStreamFrame;
        [inv getArgument:&clientSentSynStreamFrame atIndex:2];
        
        // Set the associated stream id in the syn stream frame
        // we want to send from the server.
        synStreamFrame.associatedToStreamId = clientSentSynStreamFrame.streamId;
        synReplyFrame.streamId = clientSentSynStreamFrame.streamId;
    }] _sendSynStream:[OCMArg any] streamId:0xf00ba4 closeLocal:[OCMArg anyPointer]];
    
    // 1.) Issue a HTTP request towards the server, this will
    //     send the SYN_STREAM request and wait for the SYN_REPLY.
    [partialSessionMock issueRequest:protocolRequest];
    
    // 2.) Simulate a server Tx stream SYN reply
    {
        // At this point, our synStreamFrame is populated with the
        // newly assigned streamID. We can encode it now.
        [frameEncoder encodeSynReplyFrame:synReplyFrame];
        
        // Simulate server Tx by preparing the encoded synStreamFrame
        // data inside session's inputBuffer, and trigger a fake
        // delegate call, that notifies the session about the newly received data.
        [[partialSessionMock inputBuffer] setData:accu.lastEncodedData];
        [[(SPDYSession *)partialSessionMock socket] performDelegateCall_socketDidReadData:accu.lastEncodedData withTag:100];
    };
    
    // 2.1) We should not expect any protocol errors to be issued from the client.
    [[[[partialSessionMock reject] ignoringNonObjectArgs] andForwardToRealObject] _sendRstStream:0xf00ba4 streamId:0xf00ba4];
    
    // 3.) Simulate a server Tx stream SYN request (opening a push stream)
    //     that's associated with the stream that the client created.
    {
        [frameEncoder encodeSynStreamFrame:synStreamFrame];
        [[partialSessionMock inputBuffer] setData:accu.lastEncodedData];
        [[(SPDYSession *)partialSessionMock socket] performDelegateCall_socketDidReadData:accu.lastEncodedData withTag:101];
    };
    
    [partialSessionMock verify];
}

- (void)testSYNStreamWithUnidirectionalFlagUnsetFails
{
    // Swizzle the
    [SPDYSocket performSwizzling];
    
    // Initialize encoder (we're going to use it later)
    NSError *error;
    SPDYFrameEncoderAccumulator *accu = [[SPDYFrameEncoderAccumulator alloc] init];
    SPDYFrameEncoder *frameEncoder = [[SPDYFrameEncoder alloc] initWithDelegate:accu headerCompressionLevel:0];
    
    // Prepare the SPDYSynStreamFrame
    __block SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = 100;
    synStreamFrame.unidirectional = NO; // This should cause a failure
    synStreamFrame.headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"init"};
    
    // Prepare the synReplyFrame
    SPDYSynReplyFrame *synReplyFrame = [[SPDYSynReplyFrame alloc] init];
    synReplyFrame.headers = @{@":version":@"3.1", @":status":@"200"};
    
    // Make a fake URL request
    NSURLRequest *URLRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    SPDYProtocol *protocolRequest = [[SPDYProtocol alloc] initWithRequest:URLRequest cachedResponse:nil client:nil];
    
    // Initialize a SPDYSession
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"http://mocked" error:&error];
    SPDYSession *session = [[SPDYSession alloc] initWithOrigin:origin configuration:nil cellular:NO error:&error];
    
    __autoreleasing id partialSessionMock = [OCMockObject partialMockForObject:session];
    
    // Catch the syn stream frame the client's about to send,
    // and grab the stream ID from it.
    [[[[[partialSessionMock expect] ignoringNonObjectArgs] andForwardToRealObject] andDo:^(NSInvocation *inv) {
        [inv retainArguments];
        __unsafe_unretained SPDYSynStreamFrame *clientSentSynStreamFrame;
        [inv getArgument:&clientSentSynStreamFrame atIndex:2];
        
        // Set the associated stream id in the syn stream frame
        // we want to send from the server.
        synStreamFrame.associatedToStreamId = clientSentSynStreamFrame.streamId;
        synReplyFrame.streamId = clientSentSynStreamFrame.streamId;
    }] _sendSynStream:[OCMArg any] streamId:0xf00ba4 closeLocal:[OCMArg anyPointer]];
    
    // 1.) Issue a HTTP request towards the server, this will
    //     send the SYN_STREAM request and wait for the SYN_REPLY.
    [partialSessionMock issueRequest:protocolRequest];
    
    // 2.) Simulate a server Tx stream SYN reply
    {
        // At this point, our synStreamFrame is populated with the
        // newly assigned streamID. We can encode it now.
        [frameEncoder encodeSynReplyFrame:synReplyFrame];
        
        // Simulate server Tx by preparing the encoded synStreamFrame
        // data inside session's inputBuffer, and trigger a fake
        // delegate call, that notifies the session about the newly received data.
        [[partialSessionMock inputBuffer] setData:accu.lastEncodedData];
        [[(SPDYSession *)partialSessionMock socket] performDelegateCall_socketDidReadData:accu.lastEncodedData withTag:100];
    };
    
    // 2.1) We are expecting a protocol error, since the
    //      SYN_STREAM includes an unset unidirectional flag.
    [[[[partialSessionMock expect] ignoringNonObjectArgs] andForwardToRealObject] _sendRstStream:0xf00ba4 streamId:0xf00ba4];
    
    // 3.) Simulate a server Tx stream SYN request (opening a push stream)
    //     that's associated with the stream that the client created.
    {
        [frameEncoder encodeSynStreamFrame:synStreamFrame];
        [[partialSessionMock inputBuffer] setData:accu.lastEncodedData];
        [[(SPDYSession *)partialSessionMock socket] performDelegateCall_socketDidReadData:accu.lastEncodedData withTag:101];
    };
    
    [partialSessionMock verify];
}

@end
