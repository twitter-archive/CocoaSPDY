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
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYStream.h"
#import "SPDYMockSessionTestBase.h"
#import "SPDYMockURLProtocolClient.h"

@interface SPDYStreamTest : SPDYMockSessionTestBase
@end

@implementation SPDYStreamTest

static const NSUInteger kTestDataLength = 128;
static NSMutableData *_uploadData;
static NSThread *_streamThread;

+ (void)setUp
{
    [super setUp];

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
    SPDYMockStreamDelegate *mockDelegate = [SPDYMockStreamDelegate new];
    SPDYStream *spdyStream = [SPDYStream new];
    spdyStream.delegate = mockDelegate;
    spdyStream.dataStream = [[NSInputStream alloc] initWithData:_uploadData];

    dispatch_semaphore_t main = dispatch_semaphore_create(0);
    dispatch_semaphore_t alt = dispatch_semaphore_create(0);
    mockDelegate.callback = ^{
        dispatch_semaphore_signal(main);
    };

    XCTAssertTrue([NSThread isMainThread], @"dispatch must occur from main thread");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        XCTAssertFalse([NSThread isMainThread], @"stream must be scheduled off main thread");

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

    XCTAssertTrue([mockDelegate.data isEqualToData:_uploadData]);
}

#define SPDYAssertStreamError(errorDomain, errorCode) do { \
    XCTAssertTrue(_mockURLProtocolClient.calledDidFailWithError); \
    XCTAssertNotNil(_mockURLProtocolClient.lastError); \
    XCTAssertEqualObjects(_mockURLProtocolClient.lastError.domain, (errorDomain)); \
    XCTAssertEqual(_mockURLProtocolClient.lastError.code, (errorCode)); \
} while (0)

- (void)testReceiveResponseMissingStatusCodeDoesAbort
{
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol]];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":version":@"http/1.1"};

    [stream didReceiveResponse:headers];
    SPDYAssertStreamError(NSURLErrorDomain, NSURLErrorBadServerResponse);
}

- (void)testReceiveResponseInvalidStatusCodeDoesAbort
{
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol]];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"99", @":version":@"http/1.1"};

    [stream didReceiveResponse:headers];
    SPDYAssertStreamError(NSURLErrorDomain, NSURLErrorBadServerResponse);
}

- (void)testReceiveResponseMissingVersionDoesAbort
{
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol]];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"200"};
    [stream didReceiveResponse:headers];
    SPDYAssertStreamError(NSURLErrorDomain, NSURLErrorBadServerResponse);
}

- (void)testReceiveResponseDoesSucceed
{
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol]];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"200", @":version":@"http/1.1", @"Header1":@"Value1",
                              @"HeaderMany":@[@"ValueMany1", @"ValueMany2"]};

    [stream didReceiveResponse:headers];
    XCTAssertTrue(_mockURLProtocolClient.calledDidReceiveResponse);

    NSHTTPURLResponse *response = _mockURLProtocolClient.lastResponse;
    XCTAssertNotNil(response);

    // Note: metadata adds a header
    XCTAssertTrue(response.allHeaderFields.count <= (NSUInteger)3);
    XCTAssertEqualObjects(response.allHeaderFields[@"Header1"], @"Value1");
    XCTAssertEqualObjects(response.allHeaderFields[@"HeaderMany"], @"ValueMany1, ValueMany2");
}

- (void)testReceiveResponseWithLocationDoesRedirect
{
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    _URLRequest.SPDYPriority = 3;
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.SPDYBodyFile = @"bodyfile.txt";
    _URLRequest.SPDYDeferrableInterval = 1.0;

    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol]];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"200", @":version":@"http/1.1", @"Header1":@"Value1",
                              @"location":@"newpath"};
    NSURL *redirectUrl = [NSURL URLWithString:@"http://mocked/newpath"];

    [stream didReceiveResponse:headers];
    XCTAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest);

    XCTAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.URL.absoluteString, redirectUrl.absoluteString);
    XCTAssertEqual(_mockURLProtocolClient.lastRedirectedRequest.SPDYPriority, (NSUInteger)3);
    XCTAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.HTTPMethod, @"POST");
    XCTAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.SPDYBodyFile, @"bodyfile.txt");
    XCTAssertEqual(_mockURLProtocolClient.lastRedirectedRequest.SPDYDeferrableInterval, 1.0);

    XCTAssertEqualObjects(((NSHTTPURLResponse *)_mockURLProtocolClient.lastRedirectResponse).allHeaderFields[@"Header1"], @"Value1");
}

- (void)testReceiveResponseWithLocationAnd303DoesRedirect
{
    // Test status code, method, SPDYBodyStream property, and host location change
    NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:@"foo"];
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.SPDYBodyStream = inputStream;

    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol]];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"303", @":version":@"http/1.1", @"Header1":@"Value1",
                              @"location":@"https://mocked2/newpath"};
    NSURL *redirectUrl = [NSURL URLWithString:@"https://mocked2/newpath"];

    [stream didReceiveResponse:headers];
    XCTAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest);

    XCTAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.URL.absoluteString, redirectUrl.absoluteString);
    XCTAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.HTTPMethod, @"GET", @"expect GET after 303");  // 303 means GET
    XCTAssertNil(_mockURLProtocolClient.lastRedirectedRequest.SPDYBodyStream);  // GET request must not have a body
}

@end
