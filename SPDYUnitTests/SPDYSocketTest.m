//
//  SPDYSocketTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYMockOriginEndpointManager.h"
#import "SPDYSocket.h"
#import "SPDYSocketOps.h"

@interface SPDYSocket ()
- (void)_onProxyResponse:(SPDYSocketProxyReadOp *)proxyReadOp;
@end

@interface SPDYMockSocket : SPDYSocket
@property (nonatomic, readonly) NSString *createStreamsToHostname;
@property (nonatomic, readonly) in_port_t createStreamsToPort;
@property (nonatomic, readonly) BOOL didCallScheduleRead;
@property (nonatomic, readonly) BOOL didCallScheduleWrite;
@property (nonatomic) BOOL openStreamsShouldFail;
@end

@implementation SPDYMockSocket
{
}

- (void)mockProxyResponse:(NSString *)responseString
{
    NSMutableArray *readQueue = [self readQueue];
    [self setValue:[readQueue objectAtIndex:0] forKey:@"_currentReadOp"];
    [readQueue removeObjectAtIndex:0];

    NSMutableArray *writeQueue = [self writeQueue];
    [self setValue:[writeQueue objectAtIndex:0] forKey:@"_currentWriteOp"];
    [writeQueue removeObjectAtIndex:0];

    SPDYSocketProxyReadOp *proxyReadOp = [self valueForKey:@"_currentReadOp"];
    NSData *responseData = [responseString dataUsingEncoding:NSUTF8StringEncoding];
    [proxyReadOp->_buffer setData:responseData];
    proxyReadOp->_bytesRead = responseData.length;
    [self _onProxyResponse:proxyReadOp];
}

- (NSMutableArray *)readQueue
{
    return [self valueForKey:@"_readQueue"];
}

- (NSMutableArray *)writeQueue
{
    return [self valueForKey:@"_writeQueue"];
}

- (id<SPDYSocketDelegate>)delegate
{
    return [self valueForKey:@"_delegate"];
}

- (id)initWithDelegate:(id<SPDYSocketDelegate>)delegate endpointManager:(SPDYOriginEndpointManager *)endpointManager
{
    self = [super initWithDelegate:delegate];
    [self setValue:endpointManager forKey:@"_endpointManager"];
    return self;
}

- (bool)_createStreamsToHost:(NSString *)hostname onPort:(in_port_t)port error:(NSError **)pError
{
    _createStreamsToHostname = hostname;
    _createStreamsToPort = port;
    return YES;
}

- (bool)_scheduleStreamsOnRunLoop:(NSRunLoop *)runLoop error:(NSError **)pError
{
    return YES;
}

- (bool)_openStreams:(NSError **)pError
{
    if (_openStreamsShouldFail) {
        *pError = [NSError errorWithDomain:@"UnitTest" code:1 userInfo:nil];
        _openStreamsShouldFail = NO;
        return NO;
    }
    return YES;
}

- (void)_scheduleRead
{
    _didCallScheduleRead = YES;
}

- (void)_scheduleWrite
{
    _didCallScheduleWrite = YES;
}

@end

@interface SPDYMockSocketDelegate : NSObject <SPDYSocketDelegate>
@property (nonatomic, readonly) BOOL didCallWillDisconnectWithError;
@property (nonatomic, readonly) BOOL didCallDidDisconnect;
@property (nonatomic, readonly) BOOL didCallWillConnect;
@property (nonatomic, readonly) BOOL didCallDidConnectToEndpoint;
@property (nonatomic, readonly) NSError *lastError;
@property (nonatomic, readonly) SPDYOriginEndpoint *lastEndpoint;

@property (nonatomic) BOOL shouldFailWillConnect;
@property (nonatomic) BOOL shouldStopRunLoop;

- (void)reset;

@end

@implementation SPDYMockSocketDelegate

- (void)reset
{
    _didCallWillDisconnectWithError = NO;
    _didCallDidDisconnect = NO;
    _didCallWillConnect = NO;
    _didCallDidConnectToEndpoint = NO;
    _lastError = nil;
    _shouldFailWillConnect = NO;
    _shouldStopRunLoop = NO;
}

- (void)socket:(SPDYSocket *)socket willDisconnectWithError:(NSError *)error
{
    _didCallWillDisconnectWithError = YES;
    _lastError = error;
    if (_shouldStopRunLoop) {
        CFRunLoopStop(CFRunLoopGetCurrent());
    }
}

- (void)socketDidDisconnect:(SPDYSocket *)socket
{
    _didCallDidDisconnect = YES;
}

- (bool)socketWillConnect:(SPDYSocket *)socket
{
    _didCallWillConnect = YES;
    if (_shouldStopRunLoop) {
        CFRunLoopStop(CFRunLoopGetCurrent());
    }
    return (_shouldFailWillConnect) ? false : true;
}

- (void)socket:(SPDYSocket *)socket didConnectToEndpoint:(SPDYOriginEndpoint *)endpoint
{
    _didCallDidConnectToEndpoint = YES;
    _lastEndpoint = endpoint;
}

@end

#pragma mark Test methods

@interface SPDYSocketTest : SenTestCase <SPDYSocketDelegate>
@end

@implementation SPDYSocketTest

- (SPDYMockSocket *)_createConnectedSocketWithProxyList:(NSArray *)proxyList
{
    SPDYMockSocketDelegate *socketDelegate = [[SPDYMockSocketDelegate alloc] init];
    return [self _createConnectedSocketWithProxyList:proxyList delegate:socketDelegate];
}

- (SPDYMockSocket *)_createConnectedSocketWithProxyList:(NSArray *)proxyList delegate:(SPDYMockSocketDelegate *)delegate
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];
    manager.mock_proxyList = proxyList;

    // Set up mocked socket
    SPDYMockSocket *socket = [[SPDYMockSocket alloc] initWithDelegate:delegate endpointManager:manager];
    if (delegate.shouldFailWillConnect) {
        STAssertFalse([socket connectToOrigin:origin withTimeout:(NSTimeInterval)-1 error:&error], nil);
        STAssertNotNil(error, nil);
    } else {
        STAssertTrue([socket connectToOrigin:origin withTimeout:(NSTimeInterval)-1 error:&error], nil);
        STAssertNil(error, nil);
    }
    return socket;
}

- (void)_assertProxyConnectWasInitiatedToHost:(NSString *)host port:(int)port socket:(SPDYMockSocket *)socket
{
    SPDYMockSocketDelegate *socketDelegate = socket.delegate;
    STAssertTrue(socketDelegate.didCallWillConnect, nil);
    STAssertFalse(socketDelegate.didCallWillDisconnectWithError, nil);
    STAssertFalse(socketDelegate.didCallDidDisconnect, nil);
    STAssertFalse(socketDelegate.didCallDidConnectToEndpoint, nil);

    STAssertTrue(socket.didCallScheduleRead, nil);
    STAssertTrue(socket.didCallScheduleWrite, nil);

    STAssertEqualObjects(socket.createStreamsToHostname, host, nil);
    STAssertEquals(socket.createStreamsToPort, (in_port_t)port, nil);

    STAssertTrue([[[socket readQueue] firstObject] isKindOfClass:[SPDYSocketProxyReadOp class]], nil);
    STAssertTrue([[[socket writeQueue] firstObject] isKindOfClass:[SPDYSocketProxyWriteOp class]], nil);
}

- (void)_assertDirectConnectWasInitiatedForSocket:(SPDYMockSocket *)socket
{
    SPDYMockSocketDelegate *socketDelegate = socket.delegate;
    STAssertTrue(socketDelegate.didCallWillConnect, nil);
    STAssertFalse(socketDelegate.didCallWillDisconnectWithError, nil);
    STAssertFalse(socketDelegate.didCallDidDisconnect, nil);
    STAssertFalse(socketDelegate.didCallDidConnectToEndpoint, nil);

    STAssertEqualObjects(socket.createStreamsToHostname, @"mytesthost.com", nil);
    STAssertEquals(socket.createStreamsToPort, (in_port_t)443, nil);

    STAssertEquals([[socket readQueue] count], (NSUInteger)0, nil);
    STAssertEquals([[socket writeQueue] count], (NSUInteger)0, nil);
}

#pragma mark Tests

- (void)testInitWithHttpsProxyDoesInitiateConnect
{
    SPDYMockSocket *socket = [self _createConnectedSocketWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }]];

    STAssertTrue(socket.connectedToProxy, nil);
    [self _assertProxyConnectWasInitiatedToHost:@"1.2.3.4" port:8888 socket:socket];
}

- (void)testInitWithHttpsProxyDelegateCancelsConnect
{
    // Set up mocked socket
    SPDYMockSocketDelegate *socketDelegate = [[SPDYMockSocketDelegate alloc] init];
    socketDelegate.shouldFailWillConnect = YES;

    SPDYMockSocket *socket = [self _createConnectedSocketWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }] delegate:socketDelegate];

    STAssertTrue(socketDelegate.didCallWillConnect, nil);
    STAssertTrue(socketDelegate.didCallWillDisconnectWithError, nil);
    STAssertTrue(socketDelegate.didCallDidDisconnect, nil);
    STAssertFalse(socketDelegate.didCallDidConnectToEndpoint, nil);
    STAssertNotNil(socketDelegate.lastError, nil);
    STAssertFalse(socket.didCallScheduleRead, nil);
    STAssertFalse(socket.didCallScheduleWrite, nil);
}

- (void)testConnectWithProxyWhenOpenStreamsFailsDoesReturnFalse
{
    // Set up mock origin endpoint manager to avoid getting system's real proxy config.
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"",
            (__bridge NSString *)kCFProxyPortNumberKey : @"443"
    }];

    // Set up mocked socket
    SPDYMockSocketDelegate *socketDelegate = [[SPDYMockSocketDelegate alloc] init];

    SPDYMockSocket *socket = [[SPDYMockSocket alloc] initWithDelegate:socketDelegate endpointManager:manager];
    socket.openStreamsShouldFail = YES;
    STAssertFalse([socket connectToOrigin:origin withTimeout:(NSTimeInterval)-1 error:&error], nil);
}

- (void)testConnectWithEmptyProxyAutoConfigURLDoesUseDirect
{
    // Set up mock origin endpoint manager to avoid getting system's real proxy config.
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeAutoConfigurationURL,
            (__bridge NSString *)kCFProxyAutoConfigurationURLKey : @""
    }];

    // Set up mocked socket
    SPDYMockSocketDelegate *socketDelegate = [[SPDYMockSocketDelegate alloc] init];
    socketDelegate.shouldStopRunLoop = YES;

    SPDYMockSocket *socket = [[SPDYMockSocket alloc] initWithDelegate:socketDelegate endpointManager:manager];
    STAssertTrue([socket connectToOrigin:origin withTimeout:(NSTimeInterval)-1 error:&error], nil);
    STAssertNil(error, nil);  // it's async

    CFRunLoopRun();

    STAssertFalse(socketDelegate.didCallWillDisconnectWithError, nil);
    STAssertFalse(socketDelegate.didCallDidDisconnect, nil);
    STAssertTrue(socketDelegate.didCallWillConnect, nil);
    STAssertFalse(socketDelegate.didCallDidConnectToEndpoint, nil);

    STAssertFalse(socket.didCallScheduleRead, nil);
    STAssertFalse(socket.didCallScheduleWrite, nil);

    // Since this failed trying to resolve the proxy name, we never tried to connected
    STAssertFalse(socket.connectedToProxy, nil);
}

- (void)testConnectWithProxyAndFallbackDoesConnectToDirectWhenProxyFailsOpenStream
{
    // Set up mock origin endpoint manager to avoid getting system's real proxy config.
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }, @{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeNone,
    }];

    // Set up mocked socket
    SPDYMockSocketDelegate *socketDelegate = [[SPDYMockSocketDelegate alloc] init];

    SPDYMockSocket *socket = [[SPDYMockSocket alloc] initWithDelegate:socketDelegate endpointManager:manager];
    socket.openStreamsShouldFail = YES;
    STAssertTrue([socket connectToOrigin:origin withTimeout:(NSTimeInterval)-1 error:&error], nil);
    STAssertNil(error, nil);
    [self _assertDirectConnectWasInitiatedForSocket:socket];
}

- (void)testConnectWithProxyAndFallbackDoesConnectToDirectWhenProxyFailsConnectResponse
{
    SPDYMockSocket *socket = [self _createConnectedSocketWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }, @{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeNone,
    }]];

    STAssertTrue(socket.connectedToProxy, nil);
    [self _assertProxyConnectWasInitiatedToHost:@"1.2.3.4" port:8888 socket:socket];

    SPDYMockSocketDelegate *delegate = socket.delegate;
    [delegate reset];
    [socket mockProxyResponse:@"HTTP/1.1 500 Not ok\r\n\r\n"];
    [self _assertDirectConnectWasInitiatedForSocket:socket];
}

@end
