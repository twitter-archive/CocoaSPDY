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
#import "SPDYMetadata.h"
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
    SPDYSocket *socket = [[SPDYSocket alloc] initWithDelegate:nil];

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
    [socket setCellular:YES];
    SPDYSession *session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket didConnectToHost:@"mocked.com" port:55555];

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)1, nil);
    session = [[sessionManager basePool] nextSession];
    STAssertEquals(session.activeStreams.count, (NSUInteger)0, nil);
    session = [[sessionManager wwanPool] nextSession];
    STAssertEquals(session.activeStreams.count, (NSUInteger)2, nil);

    // Force socket to close base session and remove streams
    session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)1, nil);

    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket willDisconnectWithError:nil];
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
    SPDYSocket *socket = [[SPDYSocket alloc] initWithDelegate:nil];

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
    [(id <SPDYSocketDelegate>)session socket:socket willDisconnectWithError:nil];
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

    [socket setCellular:YES];
    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket didConnectToHost:@"mocked.com" port:55555];
    STAssertTrue(session.isOpen, nil);

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
    session = [[sessionManager wwanPool] nextSession];
    STAssertEquals(session.activeStreams.count, (NSUInteger)2, nil);

    // Force socket to close wwan session and remove streams
    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);
}

- (void)testSocketAndGlobalReachabilityChangesAfterQueueingStreamDoesUpdateSessionPool
{
    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    urlRequest.SPDYDeferrableInterval = 0;
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];
    SPDYSocket *socket = [[SPDYSocket alloc] initWithDelegate:nil];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol];
    stream.request = urlRequest;

    // Force reachability to WIFI and queue stream
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);

    // Socket manages to connect to a different (WWAN) network after global reachability changes
    [sessionManager _updateReachability:(kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN)];
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)1, nil);

    [socket setCellular:YES];
    SPDYSession *session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket didConnectToHost:@"mocked.com" port:55555];

    // Session gets moved into new pool and is dispatched
    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)2, nil);
    STAssertTrue(session.isOpen, nil);
    STAssertFalse(stream.closed, nil);
}

- (void)testSocketReachabilityChangesAfterQueueingStreamThenGlobalReachabilityChangesDoesUpdateSessionPool
{
    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    urlRequest.SPDYDeferrableInterval = 0;
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];
    SPDYSocket *socket = [[SPDYSocket alloc] initWithDelegate:nil];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol];
    stream.request = urlRequest;

    // Force reachability to WIFI and queue stream
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager basePool] pendingCount], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] pendingCount], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)0, nil);

    // Socket manages to connect to a different (WWAN) network
    [socket setCellular:YES];
    SPDYSession *session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket didConnectToHost:@"mocked.com" port:55555];

    // Session gets moved into new pool, but the dispatch is for the previous pool. It will allocate
    // a new session but not dispatch the stream.
    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager basePool] pendingCount], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] pendingCount], (NSUInteger)0, nil);
    STAssertEquals([[sessionManager basePool] count], (NSUInteger)1, nil);
    STAssertEquals([[sessionManager wwanPool] count], (NSUInteger)1, nil);

    // Now the dispatch of the pending stream will happen (to the cellular pool)
    [sessionManager _updateReachability:(kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN)];
    STAssertEquals([sessionManager.pendingStreams count], (NSUInteger)0, nil);
    STAssertTrue(session.isOpen, nil);
    STAssertFalse(stream.closed, nil); // still pending, never dispatched

    SPDYMetadata *metadata = [stream metadata];
    STAssertTrue(metadata.cellular, nil);
}

@end
