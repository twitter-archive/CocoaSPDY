//
//  SPDYStreamManagerTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <XCTest/XCTest.h>
#import "SPDYStreamManager.h"
#import "SPDYStream.h"
#import "SPDYProtocol.h"

@interface SPDYStreamManagerTest : XCTestCase
@end

@interface SPDYStubbedProtocol : SPDYProtocol
@end

@implementation SPDYStubbedProtocol
- (id<NSURLProtocolClient>)client
{
    return nil;
}
@end

@interface SPDYStubbedStream : SPDYStream
+ (void)resetTestStreamIds;
- (id)initWithPriority:(uint8_t)priority;
@end

@implementation SPDYStubbedStream
{
    SPDYProtocol *_retainedProtocol;
}
static SPDYStreamId _nextStreamId;

+ (void)resetTestStreamIds
{
    _nextStreamId = 1;
}

- (id)initWithPriority:(uint8_t)priority
{
    self = [super init];
    if (self) {
        self.priority = priority;
        self.streamId = _nextStreamId;
        _nextStreamId += 1;
        if (self.local) {
            _retainedProtocol = [[SPDYStubbedProtocol alloc] init];
            self.protocol = _retainedProtocol;
        }
    }
    return self;
}

- (bool)local
{
    return self.streamId % 2 == 1;
}

@end

@implementation SPDYStreamManagerTest
{
    SPDYStreamManager *_manager;
    NSUInteger _numStreams;
}

- (void)setUp
{
    [super setUp];
    _manager = [[SPDYStreamManager alloc] init];
    _numStreams = 100;

    [SPDYStubbedStream resetTestStreamIds];
    for (NSUInteger i = 0; i < _numStreams; i++) {
        SPDYStream *stream = [[SPDYStubbedStream alloc] initWithPriority:((uint8_t)arc4random() % 8)];
        _manager[stream.streamId] = stream;
    }
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testFastIterationByPriority
{
    SPDYStream *prevStream;
    NSUInteger streamCount = 0;
    NSUInteger localStreamCount = 0;
    NSUInteger remoteStreamCount = 0;
    for (SPDYStream *stream in _manager) {
        streamCount++;
        stream.local ? localStreamCount++ : remoteStreamCount++;
        if (prevStream) {
            XCTAssertTrue(prevStream.priority <= stream.priority);
        }
        prevStream = stream;
    }
    XCTAssertEqual(streamCount, _numStreams);
    XCTAssertEqual(streamCount, _manager.count);
    XCTAssertEqual(localStreamCount, _manager.localCount);
    XCTAssertEqual(remoteStreamCount, _manager.remoteCount);
}

- (void)testSubscriptAccessors
{
    for (SPDYStream *stream in _manager) {
        XCTAssertEqual(_manager[stream.streamId], stream);
        if (stream.protocol) {
            XCTAssertEqual(_manager[stream.protocol], stream);
        }
    }
}

- (void)testStreamRemoval
{
    SPDYStream *one = _manager[4];
    SPDYStream *two = _manager[5];

    XCTAssertNotNil(one);
    XCTAssertNotNil(two);

    NSUInteger prevRemoteStreamCount = _manager.remoteCount;
    [_manager removeStreamWithStreamId:4];
    XCTAssertEqual(prevRemoteStreamCount - 1, _manager.remoteCount);

    NSUInteger prevLocalStreamCount = _manager.localCount;
    [_manager removeStreamForProtocol:two.protocol];
    XCTAssertEqual(prevLocalStreamCount - 1, _manager.localCount);

    XCTAssertNil(_manager[4]);
    XCTAssertNil(_manager[5]);

    SPDYStream *prevStream;
    NSUInteger streamCount = 0;
    for (SPDYStream *stream in _manager) {
        streamCount++;
        if (prevStream) {
            XCTAssertTrue(prevStream.priority <= stream.priority);
        }
        prevStream = stream;
    }
    XCTAssertEqual(streamCount, _numStreams - 2);
}

@end
