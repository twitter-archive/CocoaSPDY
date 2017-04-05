//
//  SPDYNSURLCachingTest.m
//  SPDY
//
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier on 11/30/15.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "SPDYIntegrationTestHelper.h"
#import "SPDYProtocol.h"

// Remove this once CocoaSPDY supports fully-featured caching

@interface SPDYNSURLCachingTest : XCTestCase<NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@end

@implementation SPDYNSURLCachingTest

+ (void)setUp
{
    [super setUp];
    [SPDYIntegrationTestHelper setUp];

    [SPDYURLConnectionProtocol registerOrigin:@"http://example.com"];

    [NSURLCache setSharedURLCache:[[NSURLCache alloc] initWithMemoryCapacity:1000000 diskCapacity:10000000 diskPath:nil]];
}

+ (void)tearDown
{
    [super tearDown];
    [SPDYIntegrationTestHelper tearDown];
}

- (void)setUp
{
    [super setUp];
    [self resetSharedCache];
}

- (void)tearDown
{
    [super tearDown];
    [self resetSharedCache];
}

- (void)resetSharedCache
{
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (NSArray *)parameterizedTestHelpers
{
    // Should behave the same
    return @[
             [[SPDYURLConnectionIntegrationTestHelper alloc] init],
             [[SPDYURLSessionIntegrationTestHelper alloc] init],
             ];
}

- (NSArray *)parameterizedTestInputs
{
    return @[
             // Request helper to use                                  Cache policy to use                     Should pull from cache
             @[ [[SPDYURLConnectionIntegrationTestHelper alloc] init], @(NSURLRequestUseProtocolCachePolicy),  @(NO) ],
             @[ [[SPDYURLSessionIntegrationTestHelper alloc] init],    @(NSURLRequestUseProtocolCachePolicy),  @(YES) ],
             @[ [[SPDYURLConnectionIntegrationTestHelper alloc] init], @(NSURLRequestReturnCacheDataElseLoad), @(YES) ],
             @[ [[SPDYURLSessionIntegrationTestHelper alloc] init],    @(NSURLRequestReturnCacheDataElseLoad), @(YES) ],
             ];
}

#pragma mark Tests

#define GET_TEST_PARAMS \
        SPDYIntegrationTestHelper *testHelper = testParams[0]; \
        NSURLRequestCachePolicy cachePolicy = [testParams[1] integerValue]; \
        BOOL shouldPullFromCache = [testParams[2] boolValue]; (void)shouldPullFromCache

- (void)testCacheableResponse_DoesInsertAndLoadFromCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);

        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should pull from cache. Create a new request object just in case.
        request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        [testHelper reset];
        [testHelper loadRequest:request];

        // Verify response was pulled from cache, not network
        XCTAssertEqual(testHelper.didLoadFromCache, shouldPullFromCache, @"%@", testHelper);
    }
}

- (void)testCachedItem_DoesHaveFreshMetadata
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Verify metadata
        SPDYMetadata *metadata = [SPDYProtocol metadataForResponse:testHelper.response];
        XCTAssertNotNil(metadata, @"%@", testHelper);
        XCTAssertEqual(metadata.loadSource, SPDYLoadSourceNetwork, @"%@", testHelper);
        XCTAssertEqual(metadata.streamId, 1, @"%@", testHelper);

        // Now make request again. Should pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        // Verify response was pulled from cache, not network
        XCTAssertEqual(testHelper.didLoadFromCache, shouldPullFromCache, @"%@", testHelper);

        // Verify metadata
        metadata = [SPDYProtocol metadataForResponse:testHelper.response];
        XCTAssertNotNil(metadata, @"%@", testHelper);
        XCTAssertEqual(metadata.loadSource,  shouldPullFromCache ? SPDYLoadSourceCache : SPDYLoadSourceNetwork, @"%@", testHelper);
        XCTAssertEqual(metadata.streamId, shouldPullFromCache ? 0 : 1, @"%@", testHelper);

        // Special logic for metadata provided by SPDYProtocolContext
        if ([testHelper isMemberOfClass:[SPDYURLSessionIntegrationTestHelper class]]) {
            SPDYURLSessionIntegrationTestHelper *testHelperURLSession = (SPDYURLSessionIntegrationTestHelper *)testHelper;
            SPDYMetadata *metadata2 = [testHelperURLSession.spdyContext metadata];

            XCTAssertNotNil(metadata2, @"%@", testHelper);
            XCTAssertEqual(metadata2.loadSource,  shouldPullFromCache ? SPDYLoadSourceCache : SPDYLoadSourceNetwork, @"%@", testHelper);
            XCTAssertEqual(metadata2.streamId, 0, @"%@", testHelper);
        }
    }
}

- (void)testWithReturnCacheDontLoadPolicy_DoesFailRequest
{
    for (SPDYIntegrationTestHelper *testHelper in [self parameterizedTestHelpers]) {
        NSLog(@"- using %@", [testHelper class]);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = NSURLRequestReturnCacheDataDontLoad;

        [testHelper loadRequest:request];

        XCTAssertFalse(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didGetError, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);
    }
}

- (void)testWithReturnCacheDontLoadPolicy_DoesUseCacheIfPopulated
{
    for (SPDYIntegrationTestHelper *testHelper in [self parameterizedTestHelpers]) {
        NSLog(@"- using %@", [testHelper class]);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = NSURLRequestUseProtocolCachePolicy;

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should pull from cache.
        request.cachePolicy = NSURLRequestReturnCacheDataDontLoad;
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromCache, @"%@", testHelper);
    }
}

- (void)testWithReloadIgnoringCachePolicy_DoesNotUseCache
{
    for (SPDYIntegrationTestHelper *testHelper in [self parameterizedTestHelpers]) {
        NSLog(@"- using %@", [testHelper class]);
        [self resetSharedCache];

        // First insert into cache
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = NSURLRequestUseProtocolCachePolicy;

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again with ReloadingIgnoringCache. Should not use cache.
        request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
    }
}

- (void)testWith404Response_DoesUseCache
{
    for (SPDYIntegrationTestHelper *testHelper in [self parameterizedTestHelpers]) {
        NSLog(@"- using %@", [testHelper class]);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

        [testHelper provideResponseWithStatus:404 cacheControl:@"public, max-age=1200" date:[NSDate date]];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromCache, @"%@", testHelper);
        XCTAssertEqual(testHelper.response.statusCode, 404ul, @"%@", testHelper);
    }
}

- (void)testWith500Response_DoesNotUseCache
{
    for (SPDYIntegrationTestHelper *testHelper in [self parameterizedTestHelpers]) {
        NSLog(@"- using %@", [testHelper class]);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

        [testHelper provideResponseWithStatus:500 cacheControl:@"public, max-age=1200" date:[NSDate date]];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should not pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        // Verify response was pulled from network
        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);
        XCTAssertEqual(testHelper.response.statusCode, 500ul, @"%@", testHelper);
    }
}

- (void)testWithCacheableRequest_WithNoCacheResponse_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        [testHelper provideBasicUncacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should not pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
    }
}

- (void)testWithNoCacheRequest_WithCacheableResponse_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;
        [request addValue:@"no-store, no-cache" forHTTPHeaderField:@"Cache-Control"];

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should not pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
    }
}

- (void)testWithNoCacheRequest_WithNoCacheResponse_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;
        [request addValue:@"no-store, no-cache" forHTTPHeaderField:@"Cache-Control"];

        [testHelper provideBasicUncacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should not pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
    }
}

- (void)testWithDifferentPathRequest_WithCacheableResponse_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should not pull from cache.
        request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path/other"]];
        request.cachePolicy = NSURLRequestUseProtocolCachePolicy;
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
    }
}

- (void)testWithNoCacheSecondRequest_WithCacheableResponse_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        // This request and response were cacheable. Verify.
        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again, but request specifies a reload.
        [request addValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
        [testHelper reset];
        [testHelper loadRequest:request];
        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);

        [request addValue:@"max-age=0" forHTTPHeaderField:@"Cache-Control"];
        [testHelper reset];
        [testHelper loadRequest:request];
        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
    }
}

- (void)testWithExpiredItem_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        [testHelper provideResponseWithStatus:200 cacheControl:@"public, max-age=1" date:[NSDate dateWithTimeIntervalSinceNow:-2]];
        [testHelper loadRequest:request];

        // This request and response were cacheable. Verify.
        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
    }
}

- (void)testRequestWithAuthorization_DoesUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, shouldPullFromCache);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;
        [request addValue:@"foo" forHTTPHeaderField:@"Authorization"];

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertEqual(testHelper.didLoadFromCache, shouldPullFromCache, @"%@", testHelper);
    }
}

- (void)disabled_testRequestWithAuthorization_DoesNotUseCache_WhenHeaderChanges
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;

        NSLog(@"- using %@, policy %tu, shouldPullFromCache %tu", [testHelper class], cachePolicy, NO);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;
        [request addValue:@"foo" forHTTPHeaderField:@"Authorization"];

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should not pull from cache.
        [testHelper reset];
        [request setValue:@"bar" forHTTPHeaderField:@"Authorization"];
        [testHelper loadRequest:request];

        XCTAssertEqual(testHelper.didLoadFromCache, NO, @"%@", testHelper);
    }
}

- (void)testResponseWithNoDate_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu", [testHelper class], cachePolicy);
        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        [testHelper provideResponseWithStatus:200 cacheControl:@"public,max-age=1200" date:nil];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);
    }
}

- (void)testPOSTRequest_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu", [testHelper class], cachePolicy);

        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.HTTPMethod = @"POST";
        request.cachePolicy = cachePolicy;

        [testHelper provideBasicCacheableResponse];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);
    }
}

- (void)testResponseNearItemCacheSize_DoesUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu", [testHelper class], cachePolicy);

        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        // Note: per observational manual testing, NSURL system has a much lower limit for item size.
        // Seems to be less than 1% of max capacity.
        // Base memory capacity 1000000, base disk capacity 10000000:
        // - Response size 50000 is ok.
        // - Response size 50001 is not ok.
        // - If memory capacity goes from 1000000 to 999999, 50000 is no longer ok.
        // - If disk capacity goes from 10000000 to 6000000, 50000 is still ok.
        // - If disk capacity goes from 10000000 to 5000000, 50000 is no longer ok.
        // So we're walking the line here with little understanding of Apple's heuristic. I thought
        // 10% was the limit, but apparently its somewhere less than 1% depending on memory/disk
        // setttings.
        // This test may need to change if this starts failing.
        NSArray *dataChunks = @[
                                [NSMutableData dataWithLength:30000],
                                [NSMutableData dataWithLength:20000],
                                ];

        [testHelper provideResponseWithStatus:200 cacheControl:@"public, max-age=1200" date:[NSDate date] dataChunks:dataChunks];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertEqual(testHelper.didLoadFromCache, shouldPullFromCache, @"%@", testHelper);
    }
}

- (void)testResponseExceedsItemCacheSize_DoesNotUseCache
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu", [testHelper class], cachePolicy);

        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        // 10% of cache. Limit is 10%. Disk capacity is set to 10M.
        NSArray *dataChunks = @[
                                [NSMutableData dataWithLength:500000],
                                [NSMutableData dataWithLength:500000],
                                ];

        [testHelper provideResponseWithStatus:200 cacheControl:@"public, max-age=1200" date:[NSDate date] dataChunks:dataChunks];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertFalse(testHelper.didCacheResponse, @"%@", testHelper);
    }
}

- (void)testCacheDoesStoreAndLoadCorrectData
{
    for (NSArray *testParams in [self parameterizedTestInputs]) {
        GET_TEST_PARAMS;
        NSLog(@"- using %@, policy %tu", [testHelper class], cachePolicy);

        [self resetSharedCache];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://example.com/test/path"]];
        request.cachePolicy = cachePolicy;

        uint8_t buffer1[50] = {0};
        uint8_t buffer2[3] = {0};
        uint8_t buffer3[50] = {0};
        const NSUInteger expectedLength = sizeof(buffer1) + sizeof(buffer2) + sizeof(buffer3);
        uint8_t finalBuffer[expectedLength];

        int i = 0;
        for (int j = 0; j < sizeof(buffer1); j++) {
            finalBuffer[i] = i % 256;
            buffer1[j] = i++ % 256;
        }
        for (int j = 0; j < sizeof(buffer2); j++) {
            finalBuffer[i] = i % 256;
            buffer2[j] = i++ % 256;
        }
        for (int j = 0; j < sizeof(buffer3); j++) {
            finalBuffer[i] = i % 256;
            buffer3[j] = i++ % 256;
        }
        NSData *finalData = [NSData dataWithBytes:finalBuffer length:expectedLength];

        NSArray *dataChunks = @[
                                [NSMutableData dataWithBytes:buffer1 length:sizeof(buffer1)],
                                [NSMutableData dataWithBytes:buffer2 length:sizeof(buffer2)],
                                [NSMutableData dataWithBytes:buffer3 length:sizeof(buffer3)],
                                ];

        [testHelper provideResponseWithStatus:200 cacheControl:@"public, max-age=1200" date:[NSDate date] dataChunks:dataChunks];
        [testHelper loadRequest:request];

        XCTAssertTrue(testHelper.didLoadFromNetwork, @"%@", testHelper);
        XCTAssertTrue(testHelper.didCacheResponse, @"%@", testHelper);

        // Now make request again. Should pull from cache.
        [testHelper reset];
        [testHelper loadRequest:request];

        XCTAssertEqual(testHelper.didLoadFromCache, shouldPullFromCache, @"%@", testHelper);
        XCTAssertEqual(testHelper.data.length, expectedLength, @"%@", testHelper);

        XCTAssertEqualObjects(testHelper.data, finalData, @"%@", testHelper);
    }
}

@end
