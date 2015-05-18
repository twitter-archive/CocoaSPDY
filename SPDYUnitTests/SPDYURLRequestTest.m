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

#import <XCTest/XCTest.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYCanonicalRequest.h"
#import "SPDYProtocol.h"

@interface SPDYURLRequestTest : XCTestCase
@end

@implementation SPDYURLRequestTest

- (NSDictionary *)headersForUrl:(NSString *)urlString
{
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request = SPDYCanonicalRequestForRequest(request);
    return [request allSPDYHeaderFields];
}

- (NSDictionary *)headersForRequest:(NSMutableURLRequest *)request
{
    request = SPDYCanonicalRequestForRequest(request);
    return [request allSPDYHeaderFields];
}

- (NSMutableURLRequest *)buildRequestForUrl:(NSString *)urlString method:(NSString *)httpMethod
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
    XCTAssertEqualObjects(headers[@":method"], @"GET");
    XCTAssertEqualObjects(headers[@":path"], @"/test/path");
    XCTAssertEqualObjects(headers[@":version"], @"HTTP/1.1");
    XCTAssertEqualObjects(headers[@":host"], @"example.com");
    XCTAssertEqualObjects(headers[@":scheme"], @"http");
    XCTAssertEqualObjects(headers[@"testheader"], @"TestValue1,TestValue2");
    XCTAssertNil(headers[@"content-type"]);  // not present by default for GET
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
    XCTAssertEqualObjects(headers[@":method"], @"HEAD");
    XCTAssertEqualObjects(headers[@":path"], @"/test/path/override");
    XCTAssertEqualObjects(headers[@":version"], @"HTTP/1.0");
    XCTAssertEqualObjects(headers[@":host"], @"override.example.com");
    XCTAssertEqualObjects(headers[@":scheme"], @"ftp");
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
    XCTAssertNil(headers[@"connection"]);
    XCTAssertNil(headers[@"keep-alive"]);
    XCTAssertNil(headers[@"proxy-connection"]);
    XCTAssertNil(headers[@"transfer-encoding"]);
}

- (void)testContentTypeHeaderDefaultForPost
{
    // Ensure SPDY adds a default content-type when request is a POST with body.
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    [request setSPDYBodyFile:@"bodyfile.json"];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@":method"], @"POST");
    XCTAssertEqualObjects(headers[@"content-type"], @"application/x-www-form-urlencoded");
}

- (void)testContentTypeHeaderCustomForPost
{
    // Ensure we can also override the default content-type.
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    [request setSPDYBodyFile:@"bodyfile.json"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@":method"], @"POST");
    XCTAssertEqualObjects(headers[@"content-type"], @"application/json");
}

- (void)testContentLengthHeaderDefaultForPostWithHTTPBody
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue]);
}

- (void)testContentLengthHeaderDefaultForPostWithInvalidSPDYBodyFile
{
    // An invalid body file will result in a size of 0
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    [request setSPDYBodyFile:@"doesnotexist.json"];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"content-length"], @"0");
}

- (void)testContentLengthHeaderDefaultForPostWithSPDYBodyStream
{
    // No default for input streams
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *dataStream = [NSInputStream inputStreamWithData:data];
    [request setSPDYBodyStream:dataStream];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"content-length"], nil);
}

- (void)testContentLengthHeaderCustomForPostWithSPDYBodyStream
{
    // No default for input streams
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *dataStream = [NSInputStream inputStreamWithData:data];
    [request setSPDYBodyStream:dataStream];
    [request setValue:@"12" forHTTPHeaderField:@"Content-Length"];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"content-length"], @"12");
}

- (void)testContentLengthHeaderCustomForPostWithHTTPBody
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];
    [request setValue:@"1" forHTTPHeaderField:@"Content-Length"];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"content-length"], @"1");
}

- (void)testContentLengthHeaderDefaultForPutWithHTTPBody
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"PUT"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue]);
}

- (void)testContentLengthHeaderDefaultForGet
{
    // Unusual but not explicitly disallowed
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"GET"];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"content-length"], nil);
}

- (void)testContentLengthHeaderDefaultForGetWithHTTPBody
{
    // Unusual but not explicitly disallowed
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"GET"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue]);
}

- (void)testAcceptEncodingHeaderDefault
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"GET"];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"accept-encoding"], @"gzip, deflate");
}

- (void)testAcceptEncodingHeaderCustom
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"GET"];
    [request setValue:@"bogus" forHTTPHeaderField:@"Accept-Encoding"];

    NSDictionary *headers = [self headersForRequest:request];
    XCTAssertEqualObjects(headers[@"accept-encoding"], @"bogus");
}

- (void)testPathHeaderWithQueryString
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/test/path?param1=value1&param2=value2"];
    XCTAssertEqualObjects(headers[@":path"], @"/test/path?param1=value1&param2=value2");
}

- (void)testPathHeaderWithQueryStringAndFragment
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/test/path?param1=value1&param2=value2#fraggles"];
    XCTAssertEqualObjects(headers[@":path"], @"/test/path?param1=value1&param2=value2#fraggles");
}

- (void)testPathHeaderWithQueryStringAndFragmentInMixedCase
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/Test/Path?Param1=Value1#Fraggles"];
    XCTAssertEqualObjects(headers[@":path"], @"/Test/Path?Param1=Value1#Fraggles");
}

- (void)testPathHeaderWithURLEncodedPath
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/test/path/%E9%9F%B3%E6%A5%BD.json"];
    XCTAssertEqualObjects(headers[@":path"], @"/test/path/%E9%9F%B3%E6%A5%BD.json");
}

- (void)testPathHeaderWithURLEncodedPathReservedChars
{
    // Besides non-ASCII characters, paths may contain any valid URL character except "?#[];".
    // Test path: /gen?#[];/sub!$&'()*+,=/unres-._~
    NSDictionary *headers = [self headersForUrl:@"http://example.com/gen%3F%23%5B%5D%3B/sub!$&'()*+,=/unres-._~?p1=v1"];
    XCTAssertEqualObjects(headers[@":path"], @"/gen%3F%23%5B%5D%3B/sub!$&'()*+,=/unres-._~?p1=v1");
}

- (void)testPathHeaderWithDoubleURLEncodedPath
{
    // Ensure double encoding "#!", "%23%21", are preserved
    NSDictionary *headers = [self headersForUrl:@"http://example.com/double%2523%2521/tail"];
    XCTAssertEqualObjects(headers[@":path"], @"/double%2523%2521/tail");

    // Ensure double encoding non-ASCII characters are preserved
    headers = [self headersForUrl:@"http://example.com/doublenonascii%25E9%259F%25B3%25E6%25A5%25BD"];
    XCTAssertEqualObjects(headers[@":path"], @"/doublenonascii%25E9%259F%25B3%25E6%25A5%25BD");
}

- (void)testPathHeaderWithURLEncodedQueryStringAndFragment
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/test/path?param1=%E9%9F%B3%E6%A5%BD#fraggles%20rule"];
    XCTAssertEqualObjects(headers[@":path"], @"/test/path?param1=%E9%9F%B3%E6%A5%BD#fraggles%20rule");
}

- (void)testPathHeaderEmpty
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com"];
    XCTAssertEqualObjects(headers[@":path"], @"/");
}

- (void)testSPDYProperties
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSInputStream *stream = [[NSInputStream alloc] initWithData:[NSData new]];
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    request.SPDYPriority = 1;
    request.SPDYDeferrableInterval = 3.95;
    request.SPDYBypass = YES;
    request.SPDYBodyStream = stream;
    request.SPDYBodyFile = @"Bodyfile.json";
    request.SPDYURLSession = urlSession;

    XCTAssertEqual(request.SPDYPriority, (NSUInteger)1);
    XCTAssertEqual(request.SPDYDeferrableInterval, (double)3.95);
    XCTAssertEqual(request.SPDYBypass, (BOOL)YES);
    XCTAssertEqual(request.SPDYBodyStream, stream);
    XCTAssertEqual(request.SPDYBodyFile, @"Bodyfile.json");
    XCTAssertEqual(request.SPDYURLSession, urlSession);

    NSMutableURLRequest *mutableCopy = [request mutableCopy];

    XCTAssertEqual(mutableCopy.SPDYPriority, (NSUInteger)1);
    XCTAssertEqual(mutableCopy.SPDYDeferrableInterval, (double)3.95);
    XCTAssertEqual(mutableCopy.SPDYBypass, (BOOL)YES);
    XCTAssertEqual(mutableCopy.SPDYBodyStream, stream);
    XCTAssertEqual(mutableCopy.SPDYBodyFile, @"Bodyfile.json");
    XCTAssertEqual(mutableCopy.SPDYURLSession, urlSession);

    NSURLRequest *immutableCopy = [request copy];

    XCTAssertEqual(immutableCopy.SPDYPriority, (NSUInteger)1);
    XCTAssertEqual(immutableCopy.SPDYDeferrableInterval, (double)3.95);
    XCTAssertEqual(immutableCopy.SPDYBypass, (BOOL)TRUE);
    XCTAssertEqual(immutableCopy.SPDYBodyStream, stream);
    XCTAssertEqual(immutableCopy.SPDYBodyFile, @"Bodyfile.json");
    XCTAssertEqual(immutableCopy.SPDYURLSession, urlSession);
}

- (void)testRequestCopyDoesRetainProperties
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];

    NSMutableURLRequest __weak *weakRequest;
    NSInputStream __weak *weakStream;
    NSString __weak *weakBodyFile;
    NSURLSession __weak *weakURLSession;
    NSURLRequest *immutableCopy;

    @autoreleasepool {
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
        request.SPDYBodyStream = [[NSInputStream alloc] initWithData:[NSData new]];
        request.SPDYBodyFile = [NSString stringWithFormat:@"Bodyfile.json"];
        request.SPDYURLSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

        weakRequest = request;
        weakStream = request.SPDYBodyStream;
        weakBodyFile = request.SPDYBodyFile;
        weakURLSession = request.SPDYURLSession;

       immutableCopy = [request copy];
    }

    XCTAssertNil(weakRequest);  // totally gone
    XCTAssertNotNil(weakStream);  // still around
    XCTAssertNotNil(weakBodyFile);  // still around
    XCTAssertNotNil(weakURLSession);  // still around

    XCTAssertEqual(immutableCopy.SPDYBodyStream, weakStream);
    XCTAssertEqual(immutableCopy.SPDYBodyFile, weakBodyFile);
    XCTAssertEqual(immutableCopy.SPDYURLSession, weakURLSession);
}

- (void)testRequestCacheEqualityDoesIgnoreProperties
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];

    // Build request with headers & properties
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:@"Bar" forHTTPHeaderField:@"Foo"];
    request.SPDYPriority = 2;
    request.SPDYURLSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    request.SPDYBodyFile = @"Bodyfile.json";

    // Build response
    NSDictionary *responseHeaders = @{@"Content-Length": @"1000", @"Cache-Control": @"max-age=3600", @"TestHeader": @"TestValue"};
    NSMutableData *responseData = [[NSMutableData alloc] initWithCapacity:1000];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:responseHeaders];
    NSCachedURLResponse *cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:response data:responseData];

    // Cache it
    NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:512000 diskCapacity:10000000 diskPath:@"testcache"];
    [cache storeCachedResponse:cachedResponse forRequest:request];

    // New request, no properties or headers
    NSMutableURLRequest *newRequest = [[NSMutableURLRequest alloc] initWithURL:url];
    NSCachedURLResponse *newCachedResponse = [cache cachedResponseForRequest:newRequest];

    XCTAssertNotNil(newCachedResponse);
    XCTAssertNil(newRequest.SPDYURLSession);
    XCTAssertEqualObjects(((NSHTTPURLResponse *)newCachedResponse.response).allHeaderFields[@"TestHeader"], @"TestValue");
}

#define EQUALITYTEST_SETUP() \
NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"]; \
NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url]; \
NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url]; \

- (void)testEqualityForIdenticalIsYes
{
    EQUALITYTEST_SETUP();

    request1.HTTPMethod = @"GET";
    request2.HTTPMethod = @"GET";
    request1.SPDYPriority = 2;
    request2.SPDYPriority = 2;
    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"Value1" forHTTPHeaderField:@"Header1"];

    XCTAssertTrue([request1 isEqual:request2]);
    NSMutableSet *set = [[NSMutableSet alloc] init];
    [set addObject:request1];
    XCTAssertTrue([set containsObject:request2]);
}

- (void)testEqualityForHTTPBodySameDataIsYes
{
    EQUALITYTEST_SETUP();

    NSMutableData *data = [[NSMutableData alloc] initWithLength:8];
    request1.HTTPBody = data;
    request2.HTTPBody = data;

    XCTAssertTrue([request1 isEqual:request2]);
}

- (void)testEqualityForHTTPBodyNilDifferenceIsYes
{
    EQUALITYTEST_SETUP();
    NSMutableData *data = [[NSMutableData alloc] initWithLength:8];
    request1.HTTPBody = data;

    XCTAssertTrue([request1 isEqual:request2]);
}

- (void)testEqualityForHTTPBodyDifferentDataIsYes
{
    EQUALITYTEST_SETUP();
    NSMutableData *data = [[NSMutableData alloc] initWithLength:8];
    NSMutableData *data2 = [[NSMutableData alloc] initWithLength:8];
    request1.HTTPBody = data;
    request2.HTTPBody = data2;

    XCTAssertTrue([request1 isEqual:request2]);
}

- (void)testEqualityForHeaderNameDifferentCaseIsYes
{
    EQUALITYTEST_SETUP();
    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"Value1" forHTTPHeaderField:@"header1"];

    XCTAssertTrue([request1 isEqual:request2]);
}

- (void)testEqualityForTimeoutIntervalDifferentIsYes
{
    EQUALITYTEST_SETUP();
    request1.timeoutInterval = 5;
    request2.timeoutInterval = 6;

    XCTAssertTrue([request1 isEqual:request2]);
}

- (void)testEqualityForHTTPMethodDifferentIsNo
{
    EQUALITYTEST_SETUP();

    request1.HTTPMethod = @"GET";
    request2.HTTPMethod = @"POST";

    XCTAssertFalse([request1 isEqual:request2]);

    NSMutableSet *set = [[NSMutableSet alloc] init];
    [set addObject:request1];
    XCTAssertFalse([set containsObject:request2]);
}

- (void)testEqualityForSPDYPriorityDifferentIsNo
{
    EQUALITYTEST_SETUP();

    request1.HTTPMethod = @"GET";
    request2.HTTPMethod = @"GET";
    request1.SPDYPriority = 2;
    request2.SPDYPriority = 3;

    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testEqualityForURLPathDifferentIsNo
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSURL *url2 = [[NSURL alloc] initWithString:@"http://example.com/test/path2"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url];
    NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url2];

    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testEqualityForURLPathCaseDifferentIsNo
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSURL *url2 = [[NSURL alloc] initWithString:@"http://example.com/test/PATH"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url];
    NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url2];

    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testEqualityForURLHostCaseDifferentIsNo
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSURL *url2 = [[NSURL alloc] initWithString:@"http://Example.com/test/path"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url];
    NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url2];

    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testEqualityForHeaderNameDifferentIsNo
{
    EQUALITYTEST_SETUP();

    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"Value1" forHTTPHeaderField:@"Header2"];

    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testEqualityForHeaderValueDifferentIsNo
{
    EQUALITYTEST_SETUP();
    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"Value2" forHTTPHeaderField:@"Header1"];

    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testEqualityForHeaderValueDifferentCaseIsNo
{
    EQUALITYTEST_SETUP();
    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"value1" forHTTPHeaderField:@"Header1"];

    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testEqualityForCachePolicyDifferentIsNo
{
    EQUALITYTEST_SETUP();
    request1.cachePolicy = NSURLCacheStorageAllowed;
    request2.cachePolicy = NSURLCacheStorageNotAllowed;

    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testEqualityForHTTPShouldHandleCookiesDifferentIsNo
{
    EQUALITYTEST_SETUP();
    request1.HTTPShouldHandleCookies = YES;
    request2.HTTPShouldHandleCookies = NO;
    
    XCTAssertFalse([request1 isEqual:request2]);
}

- (void)testCanonicalRequestAddsUserAgent
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/" method:@"GET"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    NSString *userAgent = [canonicalRequest valueForHTTPHeaderField:@"User-Agent"];
    XCTAssertNotNil(userAgent);
    XCTAssertTrue([userAgent rangeOfString:@"CFNetwork/"].location > 0);
    XCTAssertTrue([userAgent rangeOfString:@"Darwin/"].location > 0);
}

- (void)testCanonicalRequestDoesNotOverwriteUserAgent
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/" method:@"GET"];
    [request setValue:@"Foobar/2" forHTTPHeaderField:@"User-Agent"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    NSString *userAgent = [canonicalRequest valueForHTTPHeaderField:@"User-Agent"];
    XCTAssertEqualObjects(userAgent, @"Foobar/2");
}

- (void)testCanonicalRequestDoesNotOverwriteUserAgentWhenEmpty
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/" method:@"GET"];
    [request setValue:@"" forHTTPHeaderField:@"User-Agent"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    NSString *userAgent = [canonicalRequest valueForHTTPHeaderField:@"User-Agent"];
    XCTAssertEqualObjects(userAgent, @"");
}

- (void)testCanonicalRequestAddsHost
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://:80/foo" method:@"GET"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    XCTAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://localhost:80/foo");
}

- (void)testCanonicalRequestAddsEmptyPath
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com" method:@"GET"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    XCTAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://example.com/");
}

- (void)testCanonicalRequestAddsEmptyPathWithPort
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com:80" method:@"GET"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    XCTAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://example.com:80/");
}

- (void)testCanonicalRequestLowercaseHost
{
    NSURL *url1 = [NSURL URLWithString:@"https://Mocked.com/bar.json"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    XCTAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://mocked.com/bar.json");
}

- (void)testCanonicalRequestPathMissing
{
    NSURL *url1 = [NSURL URLWithString:@"https://mocked.com"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    XCTAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://mocked.com/");
}

- (void)testCanonicalRequestSchemeBad
{
    NSURL *url1 = [NSURL URLWithString:@"https:mocked.com"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    XCTAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://mocked.com/");
}

- (void)testCanonicalRequestMissingHost
{
    NSURL *url1 = [NSURL URLWithString:@"https://:443/bar.json"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    XCTAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://localhost:443/bar.json");
}

- (void)testCanonicalRequestHeaders
{
    NSURL *url1 = [NSURL URLWithString:@"https://mocked.com/bar.json"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    request1.HTTPMethod = @"POST";
    request1.SPDYBodyFile = @"bodyfile.txt";
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    XCTAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://mocked.com/bar.json");
    XCTAssertEqualObjects(canonicalRequest1.allHTTPHeaderFields[@"Content-Type"], @"application/x-www-form-urlencoded");
    XCTAssertEqualObjects(canonicalRequest1.allHTTPHeaderFields[@"Accept"], @"*/*");
    XCTAssertEqualObjects(canonicalRequest1.allHTTPHeaderFields[@"Accept-Encoding"], @"gzip, deflate");
    XCTAssertEqualObjects(canonicalRequest1.allHTTPHeaderFields[@"Accept-Language"], @"en-us");  // suspect
}

@end
