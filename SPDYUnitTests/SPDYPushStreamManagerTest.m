//
//  SPDYPushStreamManagerTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <XCTest/XCTest.h>
#import "SPDYMockSessionTestBase.h"
#import "SPDYPushStreamManager.h"
#import "SPDYMockURLProtocolClient.h"

@interface SPDYPushStreamManagerTest : SPDYMockSessionTestBase
@end

@implementation SPDYPushStreamManagerTest
{
    SPDYStream *_associatedStream;
    SPDYStream *_pushStream1;
    SPDYStream *_pushStream2;
}

- (void)setUp
{
    [super setUp];
    _associatedStream = nil;
    _pushStream1 = nil;
    _pushStream2 = nil;
}

- (void)_addTwoPushStreams
{
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    _associatedStream = [self createStream];
    _associatedStream.streamId = 1;

    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    _pushStream1 = [self createStream];
    _pushStream1.streamId = 2;
    _pushStream1.local = NO;
    _pushStream1.client = nil;
    _pushStream1.associatedStream = _associatedStream;

    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed2"]];
    _pushStream2 = [self createStream];
    _pushStream2.streamId = 4;
    _pushStream2.local = NO;
    _pushStream2.client = nil;
    _pushStream2.associatedStream = _associatedStream;

    [_pushStreamManager addStream:_pushStream1 associatedWithStream:_associatedStream];
    [_pushStreamManager addStream:_pushStream2 associatedWithStream:_associatedStream];

    XCTAssertEqual(_pushStreamManager.pushStreamCount, 2U);
    XCTAssertEqual(_pushStreamManager.associatedStreamCount, 1U);
}

- (void)testStreamForProtocolNotFound
{
    SPDYMockURLProtocolClient *mockPushURLProtocolClient = [[SPDYMockURLProtocolClient alloc] init];
    NSMutableURLRequest *pushURLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/notfound"]];
    SPDYProtocol *pushProtocolRequest = [[SPDYProtocol alloc] initWithRequest:pushURLRequest cachedResponse:nil client:mockPushURLProtocolClient];

    SPDYStream *pushStream = [_pushStreamManager streamForProtocol:pushProtocolRequest];
    XCTAssertNil(pushStream);
}

- (void)testAttachToPushRequestWillAttachToPushStream
{
    [self _addTwoPushStreams];

    SPDYStream *pushStream = [self attachToPushRequestWithUrl:@"http://mocked/pushed"];
    XCTAssertNotNil(pushStream);
    XCTAssertEqualObjects(pushStream.request.URL.absoluteString, @"http://mocked/pushed");
    XCTAssertEqual(_pushStreamManager.pushStreamCount, 1U);
    XCTAssertEqual(_pushStreamManager.associatedStreamCount, 1U);

    pushStream = [self attachToPushRequestWithUrl:@"http://mocked/pushed2"];
    XCTAssertNotNil(pushStream);
    XCTAssertEqualObjects(pushStream.request.URL.absoluteString, @"http://mocked/pushed2");
    XCTAssertEqual(_pushStreamManager.pushStreamCount, 0U);
    XCTAssertEqual(_pushStreamManager.associatedStreamCount, 1U);
}

- (void)testAttachToPushRequestWillNotAttachToAssociatedStream
{
    [self _addTwoPushStreams];

    SPDYStream *pushStream = [self attachToPushRequestWithUrl:@"http://mocked/init"];
    XCTAssertNil(pushStream);
    XCTAssertEqual(_pushStreamManager.pushStreamCount, 2U);
    XCTAssertEqual(_pushStreamManager.associatedStreamCount, 1U);
}

- (void)testAttachToPushRequestWillAttachToPushStreamAfterStopLoadingPushStream
{
    [self _addTwoPushStreams];

    // Since the associated stream is still alive, this push stream will live on
    [_pushStreamManager stopLoadingStream:_pushStream1];
    XCTAssertEqual(_pushStreamManager.pushStreamCount, 2U);
    XCTAssertEqual(_pushStreamManager.associatedStreamCount, 1U);

    SPDYStream *pushStream = [self attachToPushRequestWithUrl:@"http://mocked/pushed"];
    XCTAssertNotNil(pushStream);
    XCTAssertEqual(_pushStreamManager.pushStreamCount, 1U);

    pushStream = [self attachToPushRequestWithUrl:@"http://mocked/pushed2"];
    XCTAssertNotNil(pushStream);
    XCTAssertEqualObjects(pushStream.request.URL.absoluteString, @"http://mocked/pushed2");
    XCTAssertEqual(_pushStreamManager.pushStreamCount, 0U);
    XCTAssertEqual(_pushStreamManager.associatedStreamCount, 1U);

    [_pushStreamManager stopLoadingStream:_associatedStream];
    XCTAssertEqual(_pushStreamManager.associatedStreamCount, 0U);
}

- (void)testAttachToPushRequestWillNotAttachToPushStreamAfterStopLoadingAssociatedStream
{
    [self _addTwoPushStreams];

    [_pushStreamManager stopLoadingStream:_associatedStream];
    XCTAssertEqual(_pushStreamManager.pushStreamCount, 0U);
    XCTAssertEqual(_pushStreamManager.associatedStreamCount, 0U);
}

- (void)testAttachToPushRequestDoesMakeAllCallbacks
{
    [self _addTwoPushStreams];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://mocked/pushed"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    NSMutableData *data = [NSMutableData dataWithLength:100];

    [_pushStream1.client URLProtocol:_pushStream1.client didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [_pushStream1.client URLProtocol:_pushStream1.client didLoadData:data];
    [_pushStream1.client URLProtocol:_pushStream1.client didLoadData:data];
    [_pushStream1.client URLProtocolDidFinishLoading:_pushStream1.client];

    SPDYStream *pushStream = [self attachToPushRequestWithUrl:@"http://mocked/pushed"];
    XCTAssertNotNil(pushStream);
    XCTAssertEqualObjects(pushStream.request.URL.absoluteString, @"http://mocked/pushed");

    SPDYMockURLProtocolClient *client = pushStream.client;
    XCTAssertTrue(client.calledDidReceiveResponse);
    XCTAssertTrue(client.calledDidLoadData);
    XCTAssertFalse(client.calledDidFailWithError);
    XCTAssertTrue(client.calledDidFinishLoading);
    XCTAssertNotNil(client.lastResponse);
    XCTAssertEqual(client.lastResponse.statusCode, 200);
    XCTAssertEqual(client.lastCacheStoragePolicy, NSURLCacheStorageAllowed);
    XCTAssertEqual(client.lastData.length, 200U);
}

- (void)testAttachToPushRequestFailsAfterStreamFails
{
    [self _addTwoPushStreams];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://mocked/pushed"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    NSMutableData *data = [NSMutableData dataWithLength:100];
    NSError *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];

    [_pushStream1.client URLProtocol:_pushStream1.client didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [_pushStream1.client URLProtocol:_pushStream1.client didLoadData:data];
    [_pushStream1.client URLProtocol:_pushStream1.client didLoadData:data];
    [_pushStream1.client URLProtocol:_pushStream1.client didFailWithError:error];

    SPDYStream *pushStream = [self attachToPushRequestWithUrl:@"http://mocked/pushed"];
    XCTAssertNil(pushStream);
}

- (void)testAttachToPushRequestInMiddleDoesMakeAllCallbacks
{
    [self _addTwoPushStreams];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://mocked/pushed"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    NSMutableData *data = [NSMutableData dataWithLength:100];

    [_pushStream1.client URLProtocol:_pushStream1.client didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [_pushStream1.client URLProtocol:_pushStream1.client didLoadData:data];

    SPDYStream *pushStream = [self attachToPushRequestWithUrl:@"http://mocked/pushed"];
    XCTAssertNotNil(pushStream);
    XCTAssertEqualObjects(pushStream.request.URL.absoluteString, @"http://mocked/pushed");

    SPDYMockURLProtocolClient *client = pushStream.client;
    XCTAssertTrue(client.calledDidReceiveResponse);
    XCTAssertTrue(client.calledDidLoadData);
    XCTAssertFalse(client.calledDidFailWithError);
    XCTAssertFalse(client.calledDidFinishLoading);
    XCTAssertNotNil(client.lastResponse);
    XCTAssertEqual(client.lastData.length, 100U);

    // More data then finish
    data = [NSMutableData dataWithLength:50];
    [_pushStream1.client URLProtocol:_pushStream1.client didLoadData:data];
    [_pushStream1.client URLProtocolDidFinishLoading:_pushStream1.client];

    XCTAssertTrue(client.calledDidFinishLoading);
    XCTAssertEqual(client.lastData.length, 50U); // not an accumulator
}

@end

