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
#import <LYRCountDownLatch/LYRCountDownLatch.h>
#import "SPDYStream.h"
#import "SPDYProtocol.h"
#import "SPDYSessionManager.h"

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

void LYRTestCloseSPDYSessions()
{
    // Wait until all SPDY sessions are down
    NSArray *allSessions = [[SPDYURLSessionProtocol sessionManager] allSessions];
    NSLog(@"Closing sessions: %@", allSessions);
    if ([allSessions count] == 0) {
        NSLog(@"sadasdasdsdad");
    }
    while ([(NSNumber *)[allSessions valueForKeyPath:@"@sum.isOpen"] boolValue]) {
        [allSessions makeObjectsPerformSelector:@selector(close)];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        allSessions = [[SPDYURLSessionProtocol sessionManager] allSessions];
    }
}

- (void)testRapidRequests
{
    NSURL *URL = [NSURL URLWithString:@"http://127.0.0.1:7072/"];
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
//    configuration.enableSettingsMinorVersion = NO; // NPN override
    configuration.enableTCPNoDelay = YES;
//    configuration.tlsSettings = @{ (NSString *)kCFStreamSSLValidatesCertificateChain: @(NO),
//                                   (NSString *)kCFStreamSSLIsServer: @(NO),
////                                   (NSString *)kCFStreamSSLLevel: (NSString *)kCFStreamSocketSecurityLevelSSLv2,
//                                   (NSString *)kCFStreamSSLLevel: (NSString *)kCFStreamSocketSecurityLevelTLSv1,
////                                   (NSString *)kCFStreamSSLCertificates: @[ (__bridge id) [LYRTestingContext sharedContext].cryptographer.identityRef ]
//                                   };
    [SPDYProtocol sessionManager].configuration = configuration;
    
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.protocolClasses = @[ [SPDYURLSessionProtocol class] ];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
    for (NSUInteger i=0; i <= 5000; i++) {
        NSLog(@"\n\n\n\nExecuting iteration %lu", (unsigned long)i);
        NSURLRequest *request = [NSURLRequest requestWithURL:URL];
        LYRCountDownLatch *latch = [LYRCountDownLatch latchWithCount:1 timeoutInterval:60];
        [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!response && error) {
                NSLog(@"WTF");
            }
            [latch decrementCount];
        }] resume];
        [latch waitTilCount:0];
        if (latch.count != 0) {
            NSLog(@"Break!");
        }
        
        LYRTestCloseSPDYSessions();
    }
}

@end
