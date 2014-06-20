//
//  SPDYURLRequestTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <SenTestingKit/SenTestingKit.h>
#import "NSURLRequest+SPDYURLRequest.h"

@interface SPDYURLRequestTest : SenTestCase
@end

@implementation SPDYURLRequestTest

NSDictionary* GetHeadersFromRequest(NSString *urlString)
{
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    return [request allSPDYHeaderFields];
}

- (void)testAllSPDYHeaderFields
{
    // Test basic mainline case with a single custom multi-value header.
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:@"TestValue1" forHTTPHeaderField:@"TestHeader"];
    [request addValue:@"TestValue2" forHTTPHeaderField:@"TestHeader"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@":method"], @"GET", nil);
    STAssertEqualObjects(headers[@":path"], @"/test/path", nil);
    STAssertEqualObjects(headers[@":version"], @"HTTP/1.1", nil);
    STAssertEqualObjects(headers[@":host"], @"example.com", nil);
    STAssertEqualObjects(headers[@":scheme"], @"http", nil);
    STAssertEqualObjects(headers[@"testheader"], @"TestValue1,TestValue2", nil);
    STAssertNil(headers[@"content-type"], nil);  // not present by default for GET
}

- (void)testReservedHeaderOverrides
{
    // These are internal SPDY headers that may be overridden.
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setValue:@"HEAD" forHTTPHeaderField:@"method"];
    [request setValue:@"/test/path/override" forHTTPHeaderField:@"path"];
    [request setValue:@"HTTP/1.0" forHTTPHeaderField:@"version"];
    [request setValue:@"override.example.com" forHTTPHeaderField:@"host"];
    [request setValue:@"ftp" forHTTPHeaderField:@"scheme"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@":method"], @"HEAD", nil);
    STAssertEqualObjects(headers[@":path"], @"/test/path/override", nil);
    STAssertEqualObjects(headers[@":version"], @"HTTP/1.0", nil);
    STAssertEqualObjects(headers[@":host"], @"override.example.com", nil);
    STAssertEqualObjects(headers[@":scheme"], @"ftp", nil);
}

- (void)testInvalidHeaderKeys
{
    // These headers are not allowed by SPDY
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setValue:@"none" forHTTPHeaderField:@"Connection"];
    [request setValue:@"none" forHTTPHeaderField:@"Keep-Alive"];
    [request setValue:@"none" forHTTPHeaderField:@"Proxy-Connection"];
    [request setValue:@"none" forHTTPHeaderField:@"Transfer-Encoding"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertNil(headers[@"connection"], nil);
    STAssertNil(headers[@"keep-alive"], nil);
    STAssertNil(headers[@"proxy-connection"], nil);
    STAssertNil(headers[@"transfer-encoding"], nil);
}

- (void)testContentTypeHeaderDefaultForPost
{
    // Ensure SPDY adds a default content-type when request is a POST with body.
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setSPDYBodyFile:@"bodyfile.json"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@":method"], @"POST", nil);
    STAssertEqualObjects(headers[@"content-type"], @"application/x-www-form-urlencoded", nil);
}

- (void)testContentTypeHeaderCustomForPost
{
    // Ensure we can also override the default content-type.
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setSPDYBodyFile:@"bodyfile.json"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@":method"], @"POST", nil);
    STAssertEqualObjects(headers[@"content-type"], @"application/json", nil);
}

- (void)testPathHeaderWithQueryString
{
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com/test/path?param1=value1&param2=value2");
    STAssertEqualObjects(headers[@":path"], @"/test/path?param1=value1&param2=value2", nil);
}

- (void)testPathHeaderWithQueryStringAndFragment
{
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com/test/path?param1=value1&param2=value2#fraggles");
    STAssertEqualObjects(headers[@":path"], @"/test/path?param1=value1&param2=value2#fraggles", nil);
}

- (void)testPathHeaderWithQueryStringAndFragmentInMixedCase
{
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com/Test/Path?Param1=Value1#Fraggles");
    STAssertEqualObjects(headers[@":path"], @"/Test/Path?Param1=Value1#Fraggles", nil);
}

- (void)testPathHeaderWithURLEncodedPath
{
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com/test/path/%E9%9F%B3%E6%A5%BD.json");
    STAssertEqualObjects(headers[@":path"], @"/test/path/%E9%9F%B3%E6%A5%BD.json", nil);
}

- (void)testPathHeaderWithURLEncodedPathReservedChars
{
    // Besides non-ASCII characters, paths may contain any valid URL character except "?#[]".
    // Test path: /gen?#[]/sub!$&'()*+,;=/unres-._~
    // Note that NSURL chokes on non-encoded ";" in path, so we'll test it separately.
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com/gen%3F%23%5B%5D/sub!$&'()*+,=/unres-._~?p1=v1");
    STAssertEqualObjects(headers[@":path"], @"/gen%3F%23%5B%5D/sub!$&'()*+,=/unres-._~?p1=v1", nil);

    // Test semicolon separately
    headers = GetHeadersFromRequest(@"http://example.com/semi%3B");
    STAssertEqualObjects(headers[@":path"], @"/semi;", nil);
}

- (void)testPathHeaderWithDoubleURLEncodedPath
{
    // Ensure double encoding "#!", "%23%21", are preserved
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com/double%2523%2521/tail");
    STAssertEqualObjects(headers[@":path"], @"/double%2523%2521/tail", nil);

    // Ensure double encoding non-ASCII characters are preserved
    headers = GetHeadersFromRequest(@"http://example.com/doublenonascii%25E9%259F%25B3%25E6%25A5%25BD");
    STAssertEqualObjects(headers[@":path"], @"/doublenonascii%25E9%259F%25B3%25E6%25A5%25BD", nil);
}

- (void)testPathHeaderWithURLEncodedQueryStringAndFragment
{
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com/test/path?param1=%E9%9F%B3%E6%A5%BD#fraggles%20rule");
    STAssertEqualObjects(headers[@":path"], @"/test/path?param1=%E9%9F%B3%E6%A5%BD#fraggles%20rule", nil);
}

- (void)testSPDYProperties
{
    // Test getters/setters for all custom properties to catch any typos
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];

    [request setSPDYPriority:1];
    STAssertEquals([request SPDYPriority], (NSUInteger)1, nil);

    [request setSPDYDiscretionary:TRUE];
    STAssertEquals([request SPDYDiscretionary], (BOOL)TRUE, nil);

    [request setSPDYBypass:TRUE];
    STAssertEquals([request SPDYBypass], (BOOL)TRUE, nil);

    NSMutableData *data = [[NSMutableData alloc] initWithCapacity:4];
    NSInputStream *stream = [[NSInputStream alloc] initWithData:data];
    [request setSPDYBodyStream:stream];
    STAssertEquals([request SPDYBodyStream], stream, nil);

    [request setSPDYBodyFile:@"Bodyfile.json"];
    STAssertEquals([request SPDYBodyFile], @"Bodyfile.json", nil);
}

@end
