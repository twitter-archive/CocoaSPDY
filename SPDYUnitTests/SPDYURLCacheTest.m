//
//  SPDYURLCacheTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier on 10/6/15.
//

#import <XCTest/XCTest.h>
#import "SPDYCacheStoragePolicy.h"

// Access to private function
NSDictionary *HTTPCacheControlParameters(NSString *cacheControl);

@interface SPDYURLCacheTest : XCTestCase
@end

@implementation SPDYURLCacheTest

- (void)testCacheNotAllowedForNoResponse
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];

    NSURLCacheStoragePolicy policy = SPDYCacheStoragePolicy(request, nil);
    XCTAssertEqual(policy, NSURLCacheStorageNotAllowed);
}

- (void)testCacheAllowedFor200WithNoHeader
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"1.1" headerFields:@{@"Date":@"Wed, 25 Nov 2015 00:10:13 GMT"}];

    NSURLCacheStoragePolicy policy = SPDYCacheStoragePolicy(request, response);
    XCTAssertEqual(policy, NSURLCacheStorageAllowed);
}

- (void)testCacheAllowedFor404WithNoHeader
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:404 HTTPVersion:@"1.1" headerFields:@{@"Date":@"Wed, 25 Nov 2015 00:10:13 GMT"}];

    NSURLCacheStoragePolicy policy = SPDYCacheStoragePolicy(request, response);
    XCTAssertEqual(policy, NSURLCacheStorageAllowed);
}

- (void)testCacheNotAllowedFor400WithNoHeader
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:400 HTTPVersion:@"1.1" headerFields:@{}];

    NSURLCacheStoragePolicy policy = SPDYCacheStoragePolicy(request, response);
    XCTAssertEqual(policy, NSURLCacheStorageNotAllowed);
}

- (void)testCacheNotAllowedFor200WithNoStoreRequestHeader
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"1.1" headerFields:@{@"Date":@"Wed, 25 Nov 2015 00:10:13 GMT"}];

    NSURLCacheStoragePolicy policy = SPDYCacheStoragePolicy(request, response);
    XCTAssertEqual(policy, NSURLCacheStorageNotAllowed);
}

- (void)testCacheNotAllowedFor200WithNoStoreNoCacheRequestHeader
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:@"no-store, no-cache" forHTTPHeaderField:@"Cache-Control"];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"1.1" headerFields:@{@"Date":@"Wed, 25 Nov 2015 00:10:13 GMT"}];

    NSURLCacheStoragePolicy policy = SPDYCacheStoragePolicy(request, response);
    XCTAssertEqual(policy, NSURLCacheStorageNotAllowed);
}

- (void)testCacheAllowedFor200WithNoCacheResponseHeader
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"1.1" headerFields:@{@"Cache-Control":@"no-cache",@"Date":@"Wed, 25 Nov 2015 00:10:13 GMT"}];

    NSURLCacheStoragePolicy policy = SPDYCacheStoragePolicy(request, response);
    XCTAssertEqual(policy, NSURLCacheStorageAllowed);
}

- (void)testCacheAllowedFor200WithNoStoreResponseHeader
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"1.1" headerFields:@{@"Cache-Control":@"no-store",@"Date":@"Wed, 25 Nov 2015 00:10:13 GMT"}];

    NSURLCacheStoragePolicy policy = SPDYCacheStoragePolicy(request, response);
    XCTAssertEqual(policy, NSURLCacheStorageNotAllowed);
}

#pragma mark HTTP Cache-Control parsing tests

- (void)testOneTokenWithoutValue
{
    NSDictionary *params = HTTPCacheControlParameters(@"no-cache");
    XCTAssertEqual(params.count, 1ul);
    XCTAssertEqualObjects(params[@"no-cache"], @"");
}

- (void)testTwoTokensWithoutValues
{
    NSDictionary *params = HTTPCacheControlParameters(@"no-cache,no-store");
    XCTAssertEqual(params.count, 2ul);
    XCTAssertEqualObjects(params[@"no-cache"], @"");
    XCTAssertEqualObjects(params[@"no-store"], @"");
}

- (void)testTwoTokensWithoutValuesWithSpaces
{
    NSDictionary *params = HTTPCacheControlParameters(@" no-cache, no-store ");
    XCTAssertEqual(params.count, 2ul);
    XCTAssertEqualObjects(params[@"no-cache"], @"");
    XCTAssertEqualObjects(params[@"no-store"], @"");
}

- (void)testOneTokenWithValue
{
    NSDictionary *params = HTTPCacheControlParameters(@"max-age=5");
    XCTAssertEqual(params.count, 1ul);
    XCTAssertEqualObjects(params[@"max-age"], @"5");
}

- (void)testTwoTokensWithValues
{
    NSDictionary *params = HTTPCacheControlParameters(@"max-age=5,s-maxage=6");
    XCTAssertEqual(params.count, 2ul);
    XCTAssertEqualObjects(params[@"max-age"], @"5");
    XCTAssertEqualObjects(params[@"s-maxage"], @"6");
}

- (void)testTwoTokensWithValuesWithSpaces
{
    NSDictionary *params = HTTPCacheControlParameters(@" max-age = 5, s-maxage= 6 ");
    XCTAssertEqual(params.count, 2ul);
    XCTAssertEqualObjects(params[@"max-age"], @"5");
    XCTAssertEqualObjects(params[@"s-maxage"], @"6");
}

- (void)testOneTokenWithQuotedValue
{
    NSDictionary *params = HTTPCacheControlParameters(@"vary=\"foo\"");
    XCTAssertEqual(params.count, 1ul);
    XCTAssertEqualObjects(params[@"vary"], @"foo");
}

- (void)testTwoTokensWithQuotedValues
{
    NSDictionary *params = HTTPCacheControlParameters(@"extension=\"foo=bar\",vary=\"foo\"");
    XCTAssertEqual(params.count, 2ul);
    XCTAssertEqualObjects(params[@"extension"], @"foo=bar");
    XCTAssertEqualObjects(params[@"vary"], @"foo");
}

- (void)testTwoTokensWithQuotedValuesWithSpaces
{
    NSDictionary *params = HTTPCacheControlParameters(@" extension=\" foo = bar, baz \" , vary=\"foo\" ");
    XCTAssertEqual(params.count, 2ul);
    XCTAssertEqualObjects(params[@"extension"], @" foo = bar, baz ");
    XCTAssertEqualObjects(params[@"vary"], @"foo");
}

- (void)testTwoTokensWithQuotedValuesWithEscapedQuote
{
    // extension="foo=\"bar baz\" none",vary=foo
    NSDictionary *params = HTTPCacheControlParameters(@"extension=\"foo=\\\"bar baz\\\" none\",vary=foo");
    XCTAssertEqual(params.count, 2ul);
    XCTAssertEqualObjects(params[@"extension"], @"foo=\\\"bar baz\\\" none");
    XCTAssertEqualObjects(params[@"vary"], @"foo");
}

- (void)testEmptyQuotedValues
{
    NSDictionary *params = HTTPCacheControlParameters(@"extension=\"\\\"\\\"\",vary=\"\",term=1");
    XCTAssertEqual(params.count, 3ul);
    XCTAssertEqualObjects(params[@"extension"], @"\\\"\\\"");
    XCTAssertEqualObjects(params[@"vary"], @"");
    XCTAssertEqualObjects(params[@"term"], @"1");
}

@end