//
//  SPDYSocket+SPDYSocketMock.h
//  SPDY
//
//  Created by Klemen Verdnik on 6/10/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "SPDYSocket.h"

@interface SPDYSocket (SPDYSocketMock)

//@property (nonatomic) NSArray *responseStubs;

+ (void)performSwizzling;

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
