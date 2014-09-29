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

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYStream.h"

@interface SPDYStreamTest : SenTestCase
@end

typedef void (^SPDYAsyncTestCallback)();

@interface SPDYMockStreamDelegate : NSObject <SPDYStreamDelegate>
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, copy) SPDYAsyncTestCallback callback;
@end

@implementation SPDYMockStreamDelegate
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

- (void)streamDataFinished:(SPDYStream *)stream
{
    _callback();
}

- (void)streamCanceled:(SPDYStream *)stream
{
    // No-op
}

- (void)streamClosed:(SPDYStream *)stream
{
    // No-op
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

    STAssertTrue([producedData isEqualToData:_uploadData], nil);
}

- (void)testStreamingWithStream
{
    SPDYMockStreamDelegate *mockDelegate = [SPDYMockStreamDelegate new];
    SPDYStream *spdyStream = [SPDYStream new];
    spdyStream.delegate = mockDelegate;
    spdyStream.dataStream = [[NSInputStream alloc] initWithData:_uploadData];

    dispatch_semaphore_t main = dispatch_semaphore_create(0);
    dispatch_semaphore_t alt = dispatch_semaphore_create(0);
    mockDelegate.callback = ^{
        dispatch_semaphore_signal(main);
    };

    STAssertTrue([NSThread isMainThread], @"dispatch must occur from main thread");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        STAssertFalse([NSThread isMainThread], @"stream must be scheduled off main thread");

        [spdyStream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

        // Run off-thread runloop
        while(dispatch_semaphore_wait(main, DISPATCH_TIME_NOW)) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, YES);
        }
        dispatch_semaphore_signal(alt);
    });

    // Run main thread runloop
    while(dispatch_semaphore_wait(alt, DISPATCH_TIME_NOW)) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, YES);
    }

    STAssertTrue([mockDelegate.data isEqualToData:_uploadData], nil);
}

@end
