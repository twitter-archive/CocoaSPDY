//
//  SPDYProtocolContextTest.m
//  SPDY
//
//  Created by Kevin Goodier on 10/26/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYProtocol.h"
#import "SPDYTLSTrustEvaluator.h"

@interface SPDYProtocolContextTest : XCTestCase<SPDYURLSessionDelegate, NSURLSessionDelegate>
@end

@implementation SPDYProtocolContextTest
{
    id<SPDYProtocolContext> _spdyContext;
}

- (void)tearDown
{
    _spdyContext = nil;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didStartLoadingRequest:(NSURLRequest *)request withContext:(id<SPDYProtocolContext>)context
{
    _spdyContext = context;
}

- (void)testSPDYProtocolContextDoesProvideMetadata
{
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.protocolClasses = @[ [SPDYURLSessionProtocol class] ];
    sessionConfig.timeoutIntervalForRequest = 1.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:[NSOperationQueue currentQueue]];

    // Need a bogus endpoint that will fail quickly
    // TODO: FUTURE WORK mock SPDYSocket to avoid all network activity (and this hack)
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://127.0.0.1:12345/foo"]];
    request.SPDYURLSession = session;

    BOOL __block taskComplete;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        taskComplete = YES;
        CFRunLoopStop(CFRunLoopGetCurrent());
    }];
    XCTAssertNotNil(task);
    [task resume];

    CFAbsoluteTime timeout = CFAbsoluteTimeGetCurrent() + 5.0;
    while (!taskComplete && CFAbsoluteTimeGetCurrent() < timeout) {
        CFRunLoopRun();
    }
    XCTAssertTrue(taskComplete);

    XCTAssertNotNil(_spdyContext, @"URLSession:task:didStartLoadingRequest:withContext delegate not called");

    SPDYMetadata *metadata = [_spdyContext metadata];
    XCTAssertNotNil(metadata);
    XCTAssertEqualObjects(metadata.version, @"3.1");
}

@end

