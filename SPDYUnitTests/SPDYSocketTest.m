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

@interface SPDYMockSocket : SPDYSocket
@property (nonatomic, readonly) NSString *createStreamsToHostname;
@property (nonatomic, readonly) in_port_t createStreamsToPort;
@property (nonatomic, readonly) BOOL didCallScheduleRead;
@property (nonatomic, readonly) BOOL didCallScheduleWrite;
@end

@implementation SPDYMockSocket
{
}

- (NSMutableArray *)readQueue
{
    return [self valueForKey:@"_readQueue"];
}

- (NSMutableArray *)writeQueue
{
    return [self valueForKey:@"_writeQueue"];
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
@end

@implementation SPDYMockSocketDelegate

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

- (void)testInitWithHttpsProxyDoesInitiateConnect
{
    // Set up mock origin endpoint manager to avoid getting system's real proxy config.
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }];

    // Set up mocked socket
    SPDYMockSocketDelegate *socketDelegate = [[SPDYMockSocketDelegate alloc] init];
    SPDYMockSocket *socket = [[SPDYMockSocket alloc] initWithDelegate:socketDelegate endpointManager:manager];
    [socket connectToOrigin:origin withTimeout:(NSTimeInterval)-1 error:&error];
    STAssertNil(error, nil);

    STAssertTrue(socketDelegate.didCallWillConnect, nil);
    STAssertFalse(socketDelegate.didCallWillDisconnectWithError, nil);
    STAssertFalse(socketDelegate.didCallDidDisconnect, nil);
    STAssertFalse(socketDelegate.didCallDidConnectToEndpoint, nil);

    STAssertTrue(socket.didCallScheduleRead, nil);
    STAssertTrue(socket.didCallScheduleWrite, nil);

    STAssertEqualObjects(socket.createStreamsToHostname, @"1.2.3.4", nil);
    STAssertEquals(socket.createStreamsToPort, (in_port_t)8888, nil);

    STAssertTrue([[[socket readQueue] objectAtIndex:0] isKindOfClass:[SPDYSocketProxyReadOp class]], nil);
    STAssertTrue([[[socket writeQueue] objectAtIndex:0] isKindOfClass:[SPDYSocketProxyWriteOp class]], nil);
}

- (void)testInitWithHttpsProxyDelegateCancelsConnect
{
    // Set up mock origin endpoint manager to avoid getting system's real proxy config.
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }];


    // Set up mocked socket
    SPDYMockSocketDelegate *socketDelegate = [[SPDYMockSocketDelegate alloc] init];
    socketDelegate.shouldFailWillConnect = YES;

    SPDYMockSocket *socket = [[SPDYMockSocket alloc] initWithDelegate:socketDelegate endpointManager:manager];
    [socket connectToOrigin:origin withTimeout:(NSTimeInterval)-1 error:&error];
    STAssertNil(error, nil);

    STAssertTrue(socketDelegate.didCallWillConnect, nil);
    STAssertTrue(socketDelegate.didCallWillDisconnectWithError, nil);
    STAssertTrue(socketDelegate.didCallDidDisconnect, nil);
    STAssertFalse(socketDelegate.didCallDidConnectToEndpoint, nil);
    STAssertNotNil(socketDelegate.lastError, nil);
    STAssertFalse(socket.didCallScheduleRead, nil);
    STAssertFalse(socket.didCallScheduleWrite, nil);
}

- (void)testInitWithEmptyProxyAutoConfigURLDoesFail
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
    [socket connectToOrigin:origin withTimeout:(NSTimeInterval)-1 error:&error];
    STAssertNil(error, nil);  // it's async

    CFRunLoopRun();

    STAssertTrue(socketDelegate.didCallWillDisconnectWithError, nil);
    STAssertTrue(socketDelegate.didCallDidDisconnect, nil);
    STAssertFalse(socketDelegate.didCallWillConnect, nil);
    STAssertFalse(socketDelegate.didCallDidConnectToEndpoint, nil);

    STAssertFalse(socket.didCallScheduleRead, nil);
    STAssertFalse(socket.didCallScheduleWrite, nil);
}

@end

