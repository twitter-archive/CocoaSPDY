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

static NSMutableData *_uploadData;

+ (void)setUp
{
    _uploadData = [[NSMutableData alloc] initWithCapacity:26 * 16];
    NSData *alpha = [@"abcdefghijklmnopqrstuvwyz" dataUsingEncoding:NSUTF8StringEncoding];
    [_uploadData appendData:alpha];
    for (int i = 0; i < 4; i++) {
        [_uploadData appendData:_uploadData];
    }
}

- (void)testBodyWithData
{
    NSMutableData *producedData = [[NSMutableData alloc] initWithCapacity:26 * 16];
    SPDYStream *spdyStream = [SPDYStream new];
    spdyStream.data = _uploadData;

    __block bool finished = NO;

    STAssertTrue([NSThread isMainThread], @"dispatch must occur from main thread");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        STAssertFalse([NSThread isMainThread], @"stream must be scheduled off main thread");

        // Run off-thread runloop
        while(spdyStream.hasDataAvailable) {
            [producedData appendData:[spdyStream readData:10 error:nil]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            finished = YES;
        });
    });

    // Run main thread runloop
    while(!finished) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }

    STAssertTrue([producedData isEqualToData:_uploadData], nil);
}

- (void)testBodyStreamViaData
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

    STAssertTrue([NSThread isMainThread], @"dispatch must occur from main thread");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        STAssertFalse([NSThread isMainThread], @"stream must be scheduled off main thread");

        [spdyStream performSelector:@selector(_scheduleCFReadStream)];

        // Run off-thread runloop
        while(!finished) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });

    // Run main thread runloop
    while(!finished) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }

    STAssertTrue([mockDataDelegate.data isEqualToData:_uploadData], nil);
}

- (void)testBodyStreamViaFile
{
    SPDYMockStreamDataDelegate *mockDataDelegate = [SPDYMockStreamDataDelegate new];
    SPDYStream *spdyStream = [SPDYStream new];
    NSString *filePath = @"/var/tmp/com.twitter.spdy.StreamTestData";
    NSError *error = nil;
    NSDataWritingOptions fileOptions = NSDataWritingAtomic | NSDataWritingFileProtectionNone;
    STAssertTrue([_uploadData writeToFile:filePath options:fileOptions error:&error],
        error.localizedDescription);
    spdyStream.dataDelegate = mockDataDelegate;
    spdyStream.dataStream = [[NSInputStream alloc] initWithFileAtPath:filePath];

    __block bool finished = NO;
    mockDataDelegate.callback = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            finished = YES;
        });
    };

    STAssertTrue([NSThread isMainThread], @"dispatch must occur from main thread");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        STAssertFalse([NSThread isMainThread], @"stream must be scheduled off main thread");

        [spdyStream performSelector:@selector(_scheduleCFReadStream)];

        // Run off-thread runloop
        while(!finished) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });

    // Run main thread runloop
    while(!finished) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }

    STAssertTrue([mockDataDelegate.data isEqualToData:_uploadData], nil);
}

@end
