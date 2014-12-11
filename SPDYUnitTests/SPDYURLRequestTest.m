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
#import "SPDYProtocol.h"

@interface SPDYURLRequestTest : SenTestCase
@end

@implementation SPDYURLRequestTest

NSDictionary* GetHeadersFromRequest(NSString *urlString)
{
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    return [request allSPDYHeaderFields];
}

NSMutableURLRequest* GetRequest(NSString *urlString, NSString *httpMethod)
{
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setHTTPMethod:httpMethod];
    return request;
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
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"POST");
    [request setSPDYBodyFile:@"bodyfile.json"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@":method"], @"POST", nil);
    STAssertEqualObjects(headers[@"content-type"], @"application/x-www-form-urlencoded", nil);
}

- (void)testContentTypeHeaderCustomForPost
{
    // Ensure we can also override the default content-type.
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"POST");
    [request setSPDYBodyFile:@"bodyfile.json"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@":method"], @"POST", nil);
    STAssertEqualObjects(headers[@"content-type"], @"application/json", nil);
}

- (void)testContentLengthHeaderDefaultForPostWithHTTPBody
{
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"POST");
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue], nil);
}

- (void)testContentLengthHeaderDefaultForPostWithInvalidSPDYBodyFile
{
    // An invalid body file will result in a size of 0
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"POST");
    [request setSPDYBodyFile:@"doesnotexist.json"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"content-length"], @"0", nil);
}

- (void)testContentLengthHeaderDefaultForPostWithSPDYBodyStream
{
    // No default for input streams
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"POST");
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *dataStream = [NSInputStream inputStreamWithData:data];
    [request setSPDYBodyStream:dataStream];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"content-length"], nil, nil);
}

- (void)testContentLengthHeaderCustomForPostWithSPDYBodyStream
{
    // No default for input streams
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"POST");
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *dataStream = [NSInputStream inputStreamWithData:data];
    [request setSPDYBodyStream:dataStream];
    [request setValue:@"12" forHTTPHeaderField:@"Content-Length"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"content-length"], @"12", nil);
}

- (void)testContentLengthHeaderCustomForPostWithHTTPBody
{
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"POST");
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];
    [request setValue:@"1" forHTTPHeaderField:@"Content-Length"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"content-length"], @"1", nil);
}

- (void)testContentLengthHeaderDefaultForPutWithHTTPBody
{
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"PUT");
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue], nil);
}

- (void)testContentLengthHeaderDefaultForGet
{
    // Unusual but not explicitly disallowed
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"GET");

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"content-length"], nil, nil);
}

- (void)testContentLengthHeaderDefaultForGetWithHTTPBody
{
    // Unusual but not explicitly disallowed
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"GET");
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue], nil);
}

- (void)testAcceptEncodingHeaderDefault
{
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"GET");

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"accept-encoding"], @"gzip, deflate", nil);
}

- (void)testAcceptEncodingHeaderCustom
{
    NSMutableURLRequest *request = GetRequest(@"http://example.com/test/path", @"GET");
    [request setValue:@"bogus" forHTTPHeaderField:@"Accept-Encoding"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@"accept-encoding"], @"bogus", nil);
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

- (void)testPathHeaderEmpty
{
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com");
    STAssertEqualObjects(headers[@":path"], @"/", nil);
}

- (void)testUserAgentHeaderNotEmpty
{
    NSDictionary *headers = GetHeadersFromRequest(@"http://example.com");
    STAssertNotNil(headers[@"user-agent"], nil);
}

- (void)testSPDYProperties
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSInputStream *stream = [[NSInputStream alloc] initWithData:[NSData new]];

    request.SPDYPriority = 1;
    request.SPDYDeferrableInterval = 3.95;
    request.SPDYBypass = YES;
    request.SPDYBodyStream = stream;
    request.SPDYBodyFile = @"Bodyfile.json";

    STAssertEquals(request.SPDYPriority, (NSUInteger)1, nil);
    STAssertEquals(request.SPDYDeferrableInterval, (double)3.95, nil);
    STAssertEquals(request.SPDYBypass, (BOOL)YES, nil);
    STAssertEquals(request.SPDYBodyStream, stream, nil);
    STAssertEquals(request.SPDYBodyFile, @"Bodyfile.json", nil);

    NSMutableURLRequest *mutableCopy = [request mutableCopy];

    STAssertEquals(mutableCopy.SPDYPriority, (NSUInteger)1, nil);
    STAssertEquals(mutableCopy.SPDYDeferrableInterval, (double)3.95, nil);
    STAssertEquals(mutableCopy.SPDYBypass, (BOOL)YES, nil);
    STAssertEquals(mutableCopy.SPDYBodyStream, stream, nil);
    STAssertEquals(mutableCopy.SPDYBodyFile, @"Bodyfile.json", nil);

    NSURLRequest *immutableCopy = [request copy];

    STAssertEquals(immutableCopy.SPDYPriority, (NSUInteger)1, nil);
    STAssertEquals(immutableCopy.SPDYDeferrableInterval, (double)3.95, nil);
    STAssertEquals(immutableCopy.SPDYBypass, (BOOL)TRUE, nil);
    STAssertEquals(immutableCopy.SPDYBodyStream, stream, nil);
    STAssertEquals(immutableCopy.SPDYBodyFile, @"Bodyfile.json", nil);
}

- (void)testCanonicalRequestDoesNotAddDefaultUserAgent
{
    NSMutableURLRequest *request = GetRequest(@"http://example.com/", @"GET");
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    STAssertNil([canonicalRequest valueForHTTPHeaderField:@"User-Agent"], nil);
}

- (void)testCanonicalRequestAddsHost
{
    NSMutableURLRequest *request = GetRequest(@"http://:80/foo", @"GET");
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    STAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://localhost:80/foo", nil);
}

- (void)testCanonicalRequestAddsEmptyPath
{
    NSMutableURLRequest *request = GetRequest(@"http://example.com", @"GET");
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    STAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://example.com/", nil);
}

- (void)testCanonicalRequestAddsEmptyPathWithPort
{
    NSMutableURLRequest *request = GetRequest(@"http://example.com:80", @"GET");
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    STAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://example.com:80/", nil);
}

@end
