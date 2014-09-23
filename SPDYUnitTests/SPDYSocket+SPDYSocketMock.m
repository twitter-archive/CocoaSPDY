//
//  SPDYSocket+SPDYSocketMock.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Klemen Verdnik on 6/10/14.
//

#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYFrameDecoder.h"
#import <objc/runtime.h>

NSString * const kSPDYTSTResponseStubs = @"kSPDYTSTResponseStubs";

NSError *socketMock_lastError = nil;
SPDYFrameDecoder *socketMock_frameDecoder = nil;

@implementation SPDYSession (Test)

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


@implementation SPDYSocket (SPDYSocketMock)

+ (void)performSwizzling:(BOOL)performSwizzling
{
    // The "+ load" method is called once, very early in the application life-cycle.
    // It's called even before the "main" function is called. Beware: there's no
    // autorelease pool at this point, so avoid Objective-C calls.
    Method original, swizzle;

    original = class_getInstanceMethod(self, @selector(connectToHost:onPort:withTimeout:error:));
    swizzle = class_getInstanceMethod(self, @selector(swizzled_connectToHost:onPort:withTimeout:error:));
    if (performSwizzling) {
        method_exchangeImplementations(original, swizzle);
    } else {
        method_exchangeImplementations(swizzle, original);
    }

    original = class_getInstanceMethod(self, @selector(readDataWithTimeout:buffer:bufferOffset:maxLength:tag:));
    swizzle = class_getInstanceMethod(self, @selector(swizzled_readDataWithTimeout:buffer:bufferOffset:maxLength:tag:));
    if (performSwizzling) {
        method_exchangeImplementations(original, swizzle);
    } else {
        method_exchangeImplementations(swizzle, original);
    }

    original = class_getInstanceMethod(self, @selector(writeData:withTimeout:tag:));
    swizzle = class_getInstanceMethod(self, @selector(swizzled_writeData:withTimeout:tag:));
    if (performSwizzling) {
        method_exchangeImplementations(original, swizzle);
    } else {
        method_exchangeImplementations(swizzle, original);
    }
}

- (BOOL)swizzled_connectToHost:(NSString *)hostname
                        onPort:(in_port_t)port
                   withTimeout:(NSTimeInterval)timeout
                         error:(NSError **)pError
{
    NSLog(@"SPDYMock: Swizzled connectToHost:%@ onPost:%d withTimeout:%f", hostname, port, timeout);

    return YES;
}

- (void)swizzled_readDataWithTimeout:(NSTimeInterval)timeout
                              buffer:(NSMutableData *)buffer
                        bufferOffset:(NSUInteger)offset
                           maxLength:(NSUInteger)length
                                 tag:(long)tag
{
    NSLog(@"SPDYSocketMock::readDataWithTimeout");
}

- (void)swizzled_writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag
{
    NSLog(@"SPDYSocketMock::writeData %@", data);
    if (socketMock_frameDecoder) {
        NSError *error = nil;
        [socketMock_frameDecoder decode:(uint8_t *)data.bytes length:data.length error:&error];
        socketMock_lastError = error;
    }
}

#pragma mark - Response stubbing

//- (NSArray *)responseStubs
//{
//    return objc_getAssociatedObject(self, (__bridge const void *)(kSPDYTSTResponseStubs));
//}
//
//- (void)setResponseStubs:(NSArray *)responseStubs
//{
//    objc_setAssociatedObject(self, (__bridge const void *)(kSPDYTSTResponseStubs), responseStubs, OBJC_ASSOCIATION_COPY);
//}

#pragma mark - SPDYSocketDelegate call forwarding

- (void)performDelegateCall_socketWillDisconnectWithError:(NSError *)error
{
    [[self delegate] socket:self willDisconnectWithError:error];
}

- (void)performDelegateCall_socketDidDisconnect;
{
    [[self delegate] socketDidDisconnect:self];
}

- (void)performDelegateCall_socketDidAcceptNewSocket:(SPDYSocket *)newSocket
{
    [[self delegate] socket:self didAcceptNewSocket:newSocket];
}

- (NSRunLoop *)performDelegateCall_socketWantsRunLoopForNewSocket:(SPDYSocket *)newSocket
{
    return [[self delegate] socket:self wantsRunLoopForNewSocket:newSocket];
}

- (bool)performDelegateCall_socketWillConnect
{
    return [[self delegate] socketWillConnect:self];
}

- (void)performDelegateCall_socketDidConnectToHost:(NSString *)host port:(in_port_t)port
{
    return [[self delegate] socket:self didConnectToHost:host port:port];
}

- (void)performDelegateCall_socketDidReadData:(NSData *)data withTag:(long)tag
{
    NSLog(@"SPDYMock: socketDidReadData:%@ tag:%ld", data, tag);
    return [[self delegate] socket:self didReadData:data withTag:tag];
}

- (void)performDelegateCall_socketDidReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
    return [[self delegate] socket:self didReadPartialDataOfLength:partialLength tag:tag];
}

- (void)performDelegateCall_socketDidWriteDataWithTag:(long)tag
{
    [[self delegate] socket:self didWriteDataWithTag:tag];
}

- (void)performDelegateCall_socketDidWritePartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
    [[self delegate] socket:self didWritePartialDataOfLength:partialLength tag:tag];
}

- (NSTimeInterval)performDelegateCall_socketWillTimeoutReadWithTag:(long)tag
                                                           elapsed:(NSTimeInterval)elapsed
                                                         bytesDone:(NSUInteger)length
{
    return [[self delegate] socket:self willTimeoutReadWithTag:tag elapsed:elapsed bytesDone:length];
}

- (NSTimeInterval)performDelegateCall_socketWillTimeoutWriteWithTag:(long)tag
                                                            elapsed:(NSTimeInterval)elapsed
                                                          bytesDone:(NSUInteger)length
{
    return [[self delegate] socket:self willTimeoutWriteWithTag:tag elapsed:elapsed bytesDone:length];
}

- (bool)performDelegateCall_socketSecuredWithTrust:(SecTrustRef)trust
{
    return [[self delegate] socket:self securedWithTrust:trust];
}

@end
