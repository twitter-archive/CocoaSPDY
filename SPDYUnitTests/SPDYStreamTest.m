//
//  SPDYStreamTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <XCTest/XCTest.h>
#import "SPDYStream.h"

@interface SPDYStreamTest : XCTestCase
@end

typedef void (^SPDYAsyncTestCallback)();

@interface SPDYMockStreamDataDelegate : NSObject <SPDYStreamDataDelegate>
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, copy) SPDYAsyncTestCallback callback;
@end

@implementation SPDYMockStreamDataDelegate
{
    NSMutableData *_data;
}

- (id)init
{
    self = [super init];
    if (self) {
        _data = [NSMutableData new];
    }
    return self;
}

- (void)streamDataAvailable:(SPDYStream *)stream
{
    [_data appendData:[stream readData:10 error:nil]];
}

- (void)streamFinished:(SPDYStream *)stream
{
    _callback();
}

@end

@implementation SPDYStreamTest

static const NSUInteger kTestDataLength = 128;
static NSMutableData *_uploadData;
static NSThread *_streamThread;

+ (void)setUp
{
    _uploadData = [[NSMutableData alloc] initWithCapacity:kTestDataLength];
    for (int i = 0; i < kTestDataLength; i++) {
        [_uploadData appendBytes:&(uint32_t){ arc4random() } length:4];
    }
//    SecRandomCopyBytes(kSecRandomDefault, kTestDataLength, _uploadData.mutableBytes);
}

- (void)testStreamingWithData
{
    NSMutableData *producedData = [[NSMutableData alloc] initWithCapacity:kTestDataLength];
    SPDYStream *spdyStream = [SPDYStream new];
    spdyStream.data = _uploadData;

    while(spdyStream.hasDataAvailable) {
        [producedData appendData:[spdyStream readData:10 error:nil]];
    }

    XCTAssertTrue([producedData isEqualToData:_uploadData]);
}

- (void)testStreamingWithStream
{
    SPDYMockStreamDataDelegate *mockDataDelegate = [SPDYMockStreamDataDelegate new];
    SPDYStream *spdyStream = [SPDYStream new];
    spdyStream.dataDelegate = mockDataDelegate;
    spdyStream.dataStream = [[NSInputStream alloc] initWithData:_uploadData];

    __block bool finished = NO;
    mockDataDelegate.callback = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            finished = YES;
        });
    };

    XCTAssertTrue([NSThread isMainThread], @"dispatch must occur from main thread");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        XCTAssertFalse([NSThread isMainThread], @"stream must be scheduled off main thread");

        [spdyStream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

        // Run off-thread runloop
        while(!finished) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });

    // Run main thread runloop
    while(!finished) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }

    XCTAssertTrue([mockDataDelegate.data isEqualToData:_uploadData]);
}

@end
