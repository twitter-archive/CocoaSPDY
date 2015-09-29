//
//  SPDYSocketOpsTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <XCTest/XCTest.h>
#import "SPDYSocketOps.h"
#import "SPDYOrigin.h"

@interface SPDYSocketOpsTest : XCTestCase
@end

@implementation SPDYSocketOpsTest

- (void)testProxyWriteOpInit
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://twitter.com:443" error:&error];
    SPDYSocketProxyWriteOp *op = [[SPDYSocketProxyWriteOp alloc] initWithOrigin:origin timeout:(NSTimeInterval)-1];

    NSLog(@"%@", op);  // ensure no crash in description
    XCTAssertTrue(op->_buffer.length > 0);

    NSString *httpConnect = [[NSString alloc] initWithData:op->_buffer encoding:NSUTF8StringEncoding];
    XCTAssertTrue([httpConnect hasPrefix:@"CONNECT twitter.com:443 HTTP/1.1\r\nHost: twitter.com:443\r\n"], @"actual: %@", httpConnect);
}

- (void)testProxyReadOpInit
{
    SPDYSocketProxyReadOp *op = [[SPDYSocketProxyReadOp alloc] initWithTimeout:(NSTimeInterval)-1];

    NSLog(@"%@", op);  // ensure no crash in description
    XCTAssertFalse([op tryParseResponse]);
    XCTAssertFalse([op success]);
}

- (void)testProxyReadIncompleteTryParseFails
{
    SPDYSocketProxyReadOp *op = [[SPDYSocketProxyReadOp alloc] initWithTimeout:(NSTimeInterval)-1];
    NSString *responseStr = @"HTTP/1.1 200 Connection established\r\n\r\n";
    NSData *responseData = [responseStr dataUsingEncoding:NSUTF8StringEncoding];
    [op->_buffer setData:responseData];

    // Run through all possible substring of a valid response
    for (NSUInteger i = 0; i < responseData.length - 1; i++) {
        op->_bytesRead = i;
        XCTAssertFalse([op tryParseResponse], @"failed at length %tu of %tu", i, responseData.length);
    }

    op->_bytesRead = responseData.length;
}

- (void)testProxyReadMalformedTryParseFails
{
    SPDYSocketProxyReadOp *op = [[SPDYSocketProxyReadOp alloc] initWithTimeout:(NSTimeInterval)-1];
    // tryParseResponse is pretty forgiving actually, not much to do here
    NSArray *responseStrList = @[
            @"",
            @"\r",
            @"\n",
            @"\r\n",
            @"\n\r",
            @"\r\n\r\n",
            @" \r\n\r\n",
            @"     \r\n\r\n",
            @"\r\n \r\n",
            @"HTTP/1.1 200\r\n",
            @"HTTP/1.1  \r\n\r\n",
            @"HTTP/1.1 200 Connection \r\nestablished\r\n",
            @" HTTP/1.1 200 Connection established\r\n\r\n",
            @"HTTP/1.1  200 Connection established\r\n\r\n",
            @"200\r\n\r\n",
            @"\r\n\r\n",
    ];

    for (NSString *responseStr in responseStrList) {
        NSData *responseData = [responseStr dataUsingEncoding:NSUTF8StringEncoding];
        [op->_buffer setData:responseData];
        op->_bytesRead = responseData.length;
        XCTAssertFalse([op tryParseResponse], @"response: %@", responseStr);
    }
}

- (void)testProxyReadPoorlyFormedTryParseSucceedsButSuccessFails
{
    SPDYSocketProxyReadOp *op = [[SPDYSocketProxyReadOp alloc] initWithTimeout:(NSTimeInterval)-1];
    // tryParseResponse is pretty forgiving actually, so this is easy
    NSArray *responseStrList = @[
            @"SPDY/1.1 200 Connection established\r\n\r\n",
            @"1 2 3\r\n\r\n",
            @"HTTP/1.1 OK Connection established\r\n\r\n",
            @"200 HTTP/1.1 OK\r\n\r\n",
            @"HTTP/1.1 0 Foo\r\n\r\n",
            @"HTTP/1.1 -1 Connection established\r\n\r\n",
            @"HTTP/1.1 100 Foo\r\n\r\n",
            @"HTTP/1.1 300 Foo\r\n\r\n",
            @"HTTP/1.1 400 Foo\r\n\r\n",
            @"HTTP/1.1 500 Error\r\n\r\n",
            @"/1.1 200 Connection established\r\n\r\n",
            @"1.1 200 Connection established\r\n\r\n",
            @"GARBAGE 200 Connection established\r\n\r\n",
    ];

    for (NSString *responseStr in responseStrList) {
        NSData *responseData = [responseStr dataUsingEncoding:NSUTF8StringEncoding];
        [op->_buffer setData:responseData];
        op->_bytesRead = responseData.length;
        XCTAssertTrue([op tryParseResponse], @"response: %@", responseStr);
        XCTAssertEqual(op->_bytesParsed, responseData.length);
        XCTAssertFalse([op success], @"response: %@", responseStr);
    }
}
- (void)testProxyReadSuccessSucceeds
{
    SPDYSocketProxyReadOp *op = [[SPDYSocketProxyReadOp alloc] initWithTimeout:(NSTimeInterval)-1];
    NSArray *responseStrList = @[
            @"HTTP/1.1 200 Connection established\r\n\r\n",
            @"HTTP/1.1 200 Blah blah foo bar\r\n\r\n",
            @"HTTP/1.1 200 500\r\n\r\n",
            @"HTTP/1.1 299 Connection established\r\n\r\n",
            @"HTTP/1.0 200 Connection established\r\n\r\n",
            @"HTTP/1.1 200 Connection established\r\nHeader: Foo\r\nHeader2: Foo Bar\r\n\r\n",
            @"HTTP/1.1 200.1 Connection established\r\n\r\n",
            @"HTTP/1.1 200 Connection established\r\n\r\n",
            @"HTTP/1 200 Connection established\r\n\r\n", // questionable
            @"HTTP/1.2 200 Connection established\r\n\r\n", // questionable
            ];

    for (NSString *responseStr in responseStrList) {
        NSData *responseData = [responseStr dataUsingEncoding:NSUTF8StringEncoding];
        [op->_buffer setData:responseData];
        op->_bytesRead = responseData.length;
        XCTAssertTrue([op tryParseResponse], @"response: %@", responseStr);
        XCTAssertEqual(op->_bytesParsed, responseData.length);
        XCTAssertTrue([op success], @"response: %@", responseStr);
    }
}

- (void)testProxyReadHasExtraData
{
    // Currently not supported

    SPDYSocketProxyReadOp *op = [[SPDYSocketProxyReadOp alloc] initWithTimeout:(NSTimeInterval)-1];
    NSString *responseStr = @"HTTP/1.1 200 Connection established\r\n\r\nMore data";
    NSData *responseData = [responseStr dataUsingEncoding:NSUTF8StringEncoding];
    [op->_buffer setData:responseData];
    op->_bytesRead = responseData.length;

    XCTAssertFalse([op tryParseResponse], @"response: %@", responseStr);
    XCTAssertFalse([op success], @"response: %@", responseStr);
}

@end
