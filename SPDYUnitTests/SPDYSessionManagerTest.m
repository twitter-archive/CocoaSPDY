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

#import <XCTest/XCTest.h>
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


@interface SPDYSessionManagerTest : XCTestCase

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
    [SPDYProtocol setConfiguration:[SPDYConfiguration defaultConfiguration]];
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
        SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol pushStreamManager:nil];
        weakStream = stream;
        urlRequest.SPDYDeferrableInterval = 0;
        stream.request = urlRequest;

        // Assert initial state
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
        XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);

        // Force base pool (non-cellular) reachability and then queue the stream
        [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
        [sessionManager queueStream:stream];

        // Assert stream is queued
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);
        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
        XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);

        // Force callback to SPDYSessionManager's session:connectedToNetwork
        SPDYSession *session = [[sessionManager basePool] nextSession];
        [(id <SPDYSocketDelegate>)session socket:nil didConnectToHost:@"mocked.com" port:55555];

        // Assert stream has been dispatched
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
        XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);

        // Assert a SYN_STREAM was written to the socket
        XCTAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]]);

        // Ensure a double cancel doesn't trigger an NSAssert
        [stream cancel];
        [stream cancel];

        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);

        [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];
        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
    }

    XCTAssertNil(weakStream);
}

- (void)testAllSessionsClosingDoesFailPendingStreams
{
    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];

    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.sessionPoolSize = 2;
    configuration.enableTCPNoDelay = NO;
    [SPDYProtocol setConfiguration:configuration];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol pushStreamManager:nil];
    urlRequest.SPDYDeferrableInterval = 0;
    stream.request = urlRequest;

    // Force base pool (non-cellular) reachability and then queue the stream
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)2);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);
    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);

    // Force socket to close session #1 and remove streams
    NSError *error = [[NSError alloc] initWithDomain:@"testdomain" code:1 userInfo:nil];
    SPDYSession *session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:nil willDisconnectWithError:error];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);
    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);

    // Force socket to close session #2 and remove streams
    session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:nil willDisconnectWithError:error];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);
    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
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
        SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol pushStreamManager:nil];
        weakStream = stream;
        urlRequest.SPDYDeferrableInterval = 0;
        stream.request = urlRequest;

        // Force base pool (non-cellular) reachability and then queue the stream
        [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
        [sessionManager queueStream:stream];

        // Force callback to SPDYSessionManager's session:connectedToNetwork
        SPDYSession *session = [[sessionManager basePool] nextSession];
        [(id <SPDYSocketDelegate>)session socket:nil didConnectToHost:@"mocked.com" port:55555];
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);

        // Force socket to close session and remove streams
        [(id <SPDYSocketDelegate>)session socket:nil willDisconnectWithError:nil];

        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);

        // Force socket to disconnect and remove session
        [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
    }

    XCTAssertNil(weakStream);
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
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol pushStreamManager:nil];
    stream.request = urlRequest;
    SPDYStream *stream2 = [[SPDYStream alloc] initWithProtocol:protocol2 pushStreamManager:nil];
    stream2.request = urlRequest;

    // Force reachability and queue stream1
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);

    // Change reachability and queue stream2
    [sessionManager _updateReachability:(kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN)];
    [sessionManager queueStream:stream2];

    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)2);
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)1);

    // Force callback to SPDYSessionManager's wwan session:connectedToNetwork and dispatch stream
    [socket setCellular:YES];
    SPDYSession *session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket didConnectToHost:@"mocked.com" port:55555];

    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)1);
    session = [[sessionManager basePool] nextSession];
    XCTAssertEqual(session.activeStreams.count, (NSUInteger)0);
    session = [[sessionManager wwanPool] nextSession];
    XCTAssertEqual(session.activeStreams.count, (NSUInteger)2);

    // Force socket to close base session and remove streams
    session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)1);

    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);
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
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol pushStreamManager:nil];
    stream.request = urlRequest;
    SPDYProtocol *protocol2 = [[SPDYProtocol alloc] init];
    SPDYStream *stream2 = [[SPDYStream alloc] initWithProtocol:protocol2 pushStreamManager:nil];
    stream2.request = urlRequest;

    // Force reachability and queue stream1
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);

    // Put stream1 into wrong pool artificially
    SPDYSession *session = [[sessionManager basePool] nextSession];
    [session setCellular:true];

    // Force session connection error
    [(id <SPDYSocketDelegate>)session socket:socket willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];
    XCTAssertFalse(session.isOpen);

    // We put the stream in the basePool but it thinks it is wwan. Because the socket failed to
    // connect, and there are no outstanding sessions, pending requests all fail.
    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);

    // Change reachability. This will dispatch. We'll also force a dispatch.
    [sessionManager _updateReachability:(kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN)];
    [sessionManager queueStream:stream2];

    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)1);

    [socket setCellular:YES];
    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket didConnectToHost:@"mocked.com" port:55555];
    XCTAssertTrue(session.isOpen);

    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
    session = [[sessionManager wwanPool] nextSession];
    XCTAssertEqual(session.activeStreams.count, (NSUInteger)1);

    // Force socket to close wwan session and remove streams
    session = [[sessionManager wwanPool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket willDisconnectWithError:nil];
    [(id <SPDYSocketDelegate>)session socketDidDisconnect:nil];

    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);
}

- (void)_commonSocketAndGlobalReachabilityChangesAfterQueueingStreamDoesUpdateSessionPool:(BOOL)moveSession
{
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.sessionPoolSize = 1;
    configuration.enableTCPNoDelay = NO;
    configuration.enforceSessionPoolCorrectness = moveSession;
    [SPDYProtocol setConfiguration:configuration];

    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    urlRequest.SPDYDeferrableInterval = 0;
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];
    SPDYSocket *socket = [[SPDYSocket alloc] initWithDelegate:nil];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol pushStreamManager:nil];
    stream.request = urlRequest;

    // Force reachability to WIFI and queue stream
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);

    // Socket manages to connect to a different (WWAN) network after global reachability changes
    [sessionManager _updateReachability:(kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN)];
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)1);

    // Session in WIFI pool connects over WWAN
    [socket setCellular:YES];
    SPDYSession *session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket didConnectToHost:@"mocked.com" port:55555];

    if (moveSession) {
        // Session gets moved into new pool and is dispatched
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)0);
        XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)2);
    } else {
        // Session is not moved into new pool and request is not dispatched (WWAN session still connecting)
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);
        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
        XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)1);
    }

    XCTAssertTrue(session.isOpen);
    XCTAssertFalse(stream.closed);
}

- (void)testSocketAndGlobalReachabilityChangesAfterQueueingStreamDoesUpdateSessionPool
{
    [self _commonSocketAndGlobalReachabilityChangesAfterQueueingStreamDoesUpdateSessionPool:YES];
}

- (void)testSocketAndGlobalReachabilityChangesAfterQueueingStreamDoesNotUpdateSessionPool
{
    [self _commonSocketAndGlobalReachabilityChangesAfterQueueingStreamDoesUpdateSessionPool:NO];
}

- (void)_commonSocketReachabilityChangesAfterQueueingStreamThenGlobalReachabilityChangesDoesUpdateSessionPool:(BOOL)moveSession
{
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.sessionPoolSize = 1;
    configuration.enableTCPNoDelay = NO;
    configuration.enforceSessionPoolCorrectness = moveSession;
    [SPDYProtocol setConfiguration:configuration];

    NSString *url = [self nextOriginUrl];
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:url error:nil];
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    urlRequest.SPDYDeferrableInterval = 0;
    SPDYSessionManager *sessionManager = [SPDYSessionManager localManagerForOrigin:origin];
    SPDYSocket *socket = [[SPDYSocket alloc] initWithDelegate:nil];

    SPDYProtocol *protocol = [[SPDYProtocol alloc] init];
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol pushStreamManager:nil];
    stream.request = urlRequest;

    // Force reachability to WIFI and queue stream
    [sessionManager _updateReachability:kSCNetworkReachabilityFlagsReachable];
    [sessionManager queueStream:stream];

    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager basePool] pendingCount], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] pendingCount], (NSUInteger)0);
    XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
    XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);

    // Socket manages to connect to a different (WWAN) network
    [socket setCellular:YES];
    SPDYSession *session = [[sessionManager basePool] nextSession];
    [(id <SPDYSocketDelegate>)session socket:socket didConnectToHost:@"mocked.com" port:55555];

    if (moveSession) {
        // Session gets moved into new pool, but the dispatch is for the previous pool. It will allocate
        // a new session but not dispatch the stream.
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)1);
        XCTAssertEqual([[sessionManager basePool] pendingCount], (NSUInteger)1);
        XCTAssertEqual([[sessionManager wwanPool] pendingCount], (NSUInteger)0);
        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
        XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)1);
    } else {
        // Session is not moved into new pool, dispatch happens. No additional session is created.
        XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
        XCTAssertEqual([[sessionManager basePool] pendingCount], (NSUInteger)0);
        XCTAssertEqual([[sessionManager wwanPool] pendingCount], (NSUInteger)0);
        XCTAssertEqual([[sessionManager basePool] count], (NSUInteger)1);
        XCTAssertEqual([[sessionManager wwanPool] count], (NSUInteger)0);
    }

    // Now the dispatch of the pending stream will happen (to the cellular pool)
    [sessionManager _updateReachability:(kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsIsWWAN)];
    XCTAssertEqual([sessionManager.pendingStreams count], (NSUInteger)0);
    XCTAssertTrue(session.isOpen);
    XCTAssertFalse(stream.closed); // still pending, never dispatched

    SPDYMetadata *metadata = [stream metadata];
    XCTAssertTrue(metadata.cellular);

}

- (void)testSocketReachabilityChangesAfterQueueingStreamThenGlobalReachabilityChangesDoesUpdateSessionPool
{
    [self _commonSocketReachabilityChangesAfterQueueingStreamThenGlobalReachabilityChangesDoesUpdateSessionPool:YES];
}

- (void)testSocketReachabilityChangesAfterQueueingStreamThenGlobalReachabilityChangesDoesNotUpdateSessionPool
{
    [self _commonSocketReachabilityChangesAfterQueueingStreamThenGlobalReachabilityChangesDoesUpdateSessionPool:NO];
}

@end
