//
//  SPDYSocket+SPDYSocketMock.m
//  SPDY
//
//  Created by Klemen Verdnik on 6/10/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "SPDYSocket+SPDYSocketMock.h"
#import <objc/runtime.h>

NSString * const kSPDYTSTResponseStubs = @"kSPDYTSTResponseStubs";

@interface SPDYSocket (Private)

@end

@implementation SPDYSocket (SPDYSocketMock)

+ (void)performSwizzling
{
    // The "+ load" method is called once, very early in the application life-cycle.
    // It's called even before the "main" function is called. Beware: there's no
    // autorelease pool at this point, so avoid Objective-C calls.
    Method original, swizzle;
    
    original = class_getInstanceMethod(self, @selector(connectToHost:onPort:withTimeout:error:));
    swizzle = class_getInstanceMethod(self, @selector(swizzled_connectToHost:onPort:withTimeout:error:));
    method_exchangeImplementations(original, swizzle);
    
    original = class_getInstanceMethod(self, @selector(readDataWithTimeout:buffer:bufferOffset:maxLength:tag:));
    swizzle = class_getInstanceMethod(self, @selector(swizzled_readDataWithTimeout:buffer:bufferOffset:maxLength:tag:));
    method_exchangeImplementations(original, swizzle);
    
    original = class_getInstanceMethod(self, @selector(writeData:withTimeout:tag:));
    swizzle = class_getInstanceMethod(self, @selector(swizzled_writeData:withTimeout:tag:));
    method_exchangeImplementations(original, swizzle);
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
    NSLog(@"SPDYMock: waiting for incoming data ...");
}

- (void)swizzled_writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag
{
    NSLog(@"SPDYMock: writing data and shit: %@", data);
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
