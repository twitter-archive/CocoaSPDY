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

@end