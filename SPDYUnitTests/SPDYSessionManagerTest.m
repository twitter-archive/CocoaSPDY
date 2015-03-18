//
//  SPDYSessionManagerTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <SenTestingKit/SenTestingKit.h>
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYSession.h"
#import "SPDYSessionManager.h"
#import "SPDYSessionPool.h"
#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYStream.h"
#import "SPDYProtocol.h"
#import "SPDYOrigin.h"
#import "SPDYStreamManager.h"
#import "SPDYMockFrameDecoderDelegate.h"

@interface SPDYSessionManager ()
@property (nonatomic, readonly) SPDYStreamManager *pendingStreams;
@property (nonatomic, readonly) SPDYSessionPool *basePool;
@property (nonatomic, readonly) SPDYSessionPool *wwanPool;
- (void)_updateReachability:(SCNetworkReachabilityFlags)flags;
@end

@implementation SPDYSessionManager (Test)

- (SPDYStreamManager *)pendingStreams
{
    return [self valueForKey:@"_pendingStreams"];
}

- (SPDYSessionPool *)basePool
{
    return [self valueForKey:@"_basePool"];
}

- (SPDYSessionPool *)wwanPool
{
    return [self valueForKey:@"_wwanPool"];
}

@end


@interface SPDYSessionManagerTest : SenTestCase

@end

@implementation SPDYSessionManagerTest
{
    SPDYMockFrameDecoderDelegate *_mockDecoderDelegate;
}

- (void)setUp
{
    [super setUp];
    [SPDYSocket performSwizzling:YES];
    _mockDecoderDelegate = [[SPDYMockFrameDecoderDelegate alloc] init];
    socketMock_frameDecoder = [[SPDYFrameDecoder alloc] initWithDelegate:_mockDecoderDelegate];

    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.sessionPoolSize = 1;
    configuration.enableTCPNoDelay = NO;
    [SPDYProtocol setConfiguration:configuration];
}

- (void)tearDown
{
    socketMock_frameDecoder = nil;
    [SPDYSocket performSwizzling:NO];
    [super tearDown];
}

- (NSString *)nextOriginUrl
{
    static int sCount = 0;
    return [NSString stringWithFormat:@"https://mocked%d.com", sCount++];
}

- (void)testDispatchQueuedStreamThenDoubleCanceledDoesReleaseStreamAndNotAssert
{
    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYStream * __weak weakStream = nil;
    @autoreleasepool {
        SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol];
        weakStream = stream;
        urlRequest.SPDYDeferrableInterval = 0;
        stream.request = urlRequest;

        // Assert initial state
        STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
        STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
        STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);

        // Force base pool (non-cellular) reachability and then queue the stream
        [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
        [sessionManager queueStream:stream];

        // Assert stream is queued
        STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)1, nil);
        STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
        STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);

        // Force callback to SPDYSessionManager's session:connectedToNetwork
        SPDYSession *session = [[sessionManager basePool] nextSession];
        [(id <SPDYSocketDelegate>)session socket:nil didConnectToHost:@"mocked.com" port:55555];

        // Assert stream has been dispatched
        STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
        STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
        STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);

        // Assert a SYN_STREAM was written to the socket
        STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]], nil);

        // Ensure a double cancel doesn't trigger an NSAssert
        [stream cancel];
        [stream cancel];

        STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);

        [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];
        STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
    }

    STAssertNil(weakStream, nil);
}

- (void)testDispatchQueuedStreamThenSessionClosesDoesReleaseStreamAndRemoveSession
{
    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYStream * __weak weakStream = nil;
    @autoreleasepool {
        SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol];
        weakStream = stream;
        urlRequest.SPDYDeferrableInterval = 0;
        stream.request = urlRequest;

        // Force base pool (non-cellular) reachability and then queue the stream
        [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
        [sessionManager queueStream:stream];

        // Force callback to SPDYSessionManager's session:connectedToNetwork
        SPDYSession *session = [[sessionManager basePool] nextSession];
        [(id <SPDYSocketDelegate>)session socket:nil didConnectToHost:@"mocked.com" port:55555];

        // Force socket to close session and remove streams
        [(id <SPDYSocketDelegate>)session socket:nil willDisconnectWithError:nil];

        STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
        STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);

        // Force socket to disconnect and remove session
        [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

        STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
        STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
    }

    STAssertNil(weakStream, nil);
}

- (void)testReachabilityChangesAfterQueueingStreamDoesDispatchNewStreamToNewSession
{
    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    urlRequest.SPDYDeferrableInterval = 0;
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYProtocol *protocol2 = [[SPDYProtocol alloc] init];
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol];
    stream.request = urlRequest;
    SPDYStream *stream2 = [[SPDYStream alloc] initWithProtocol:protocol2];
    stream2.request = urlRequest;

    // Force reachability and queue stream1
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);

    // Change reachability and queue stream2
    [sessionManager _updateReachability:(kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN)];
    [sessionManager queueStream:stream2];

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)2, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)1, nil);

    // Force callback to SPDYSessionManager's wwan session:connectedToNetwork and dispatch stream
    SPDYSession *session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:nil didConnectToHost:@"mocked.com" port:55555];

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)1, nil);
    session = [[sessionManager basePool] nextSession];
    STAssertEquals(session.activeStreams.count, (NSUInteger)0, nil);
    session = [[sessionManager wwanPool] nextSession];
    STAssertEquals(session.activeStreams.count, (NSUInteger)2, nil);

    // Force socket to close base session and remove streams
    session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:nil willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)1, nil);

    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:nil willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);
}

- (void)testQueueStreamToWrongPoolAndReachabilityChangesBeforeConnectionFailsDoesDispatchToNewSession
{
    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    urlRequest.SPDYDeferrableInterval = 0;
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol];
    stream.request = urlRequest;
    SPDYProtocol *protocol2 = [[SPDYProtocol alloc] init];
    SPDYStream *stream2 = [[SPDYStream alloc] initWithProtocol:protocol2];
    stream2.request = urlRequest;

    // Force reachability and queue stream1
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);

    // Put stream1 into wrong pool artificially
    SPDYSession *session = [[sessionManager basePool] nextSession];
    [session setCellular:true];

    // Force session connection error
    [(id <SPDYSocketDelegate>)session socket:nil willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];
    STAssertFalse(session.isOpen, nil);

    // We put the stream in the basePool but it thinks it is wwan. That case *should* be handled
    // by the session manager.
    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);

    // Change reachability. This will dispatch. We'll also force a dispatch.
    [sessionManager _updateReachability:(kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN)];
    [sessionManager queueStream:stream2];

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)2, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)1, nil);

    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:nil didConnectToHost:@"mocked.com" port:55555];
    STAssertTrue(session.isOpen, nil);

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
    session = [[sessionManager wwanPool] nextSession];
    STAssertEquals(session.activeStreams.count, (NSUInteger)2, nil);

    // Force socket to close wwan session and remove streams
    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:nil willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);
}

@end
