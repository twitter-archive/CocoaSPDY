//
//  SPDYSocket+SPDYSocketMock.h
//  SPDY
//
//  Created by Klemen Verdnik on 6/10/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "SPDYSocket.h"
#import "SPDYSession.h"

@class SPDYFrameDecoder;

// Note: these are exposed as globals only because we don't control the creation of the
// SPDYSocket inside CocoaSPDY, and we cannot add ivars in a category. This is the best
// I could do without a proper mocking library. Since these are only used by the unit
// tests, it's a (barely) acceptable solution.
extern NSError *socketMock_lastError;
extern SPDYFrameDecoder *socketMock_frameDecoder;

// Swizzles functions that connection/read/write data and allows the tests to call the delegate
// functions inside SPDYSocket which end up calling into SPDYSession.
@interface SPDYSocket (SPDYSocketMock)

//@property (nonatomic) NSArray *responseStubs;

+ (void)performSwizzling:(BOOL)performSwizzling;

#pragma mark - SPDYSocketDelegate call forwarding
- (void)performDelegateCall_socketWillDisconnectWithError:(NSError *)error;
- (void)performDelegateCall_socketDidDisconnect;
- (void)performDelegateCall_socketDidAcceptNewSocket:(SPDYSocket *)newSocket;
- (NSRunLoop *)performDelegateCall_socketWantsRunLoopForNewSocket:(SPDYSocket *)newSocket;
- (bool)performDelegateCall_socketWillConnect;
- (void)performDelegateCall_socketDidConnectToHost:(NSString *)host port:(in_port_t)port;
- (void)performDelegateCall_socketDidReadData:(NSData *)data withTag:(long)tag;
- (void)performDelegateCall_socketDidReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag;
- (void)performDelegateCall_socketDidWriteDataWithTag:(long)tag;
- (void)performDelegateCall_socketDidWritePartialDataOfLength:(NSUInteger)partialLength tag:(long)tag;
- (NSTimeInterval)performDelegateCall_socketWillTimeoutReadWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length;
- (NSTimeInterval)performDelegateCall_socketWillTimeoutWriteWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length;
- (bool)performDelegateCall_socketSecuredWithTrust:(SecTrustRef)trust;

@end

// Expose some private things in SPDYSession needed by the socket mocker.
@interface SPDYSession ()

@property (nonatomic, readonly) SPDYSocket *socket;

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
