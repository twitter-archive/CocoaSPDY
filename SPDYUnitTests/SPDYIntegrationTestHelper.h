//
//  SPDYIntegrationTestHelper.h
//  SPDY
//
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier on 11/30/15.
//

#import <Foundation/Foundation.h>

@class SPDYStream;
@protocol SPDYProtocolContext;

// Base class. Should use one of the specific implementations below.
@interface SPDYIntegrationTestHelper : NSObject

@property (nonatomic) SPDYStream *stream;
@property (nonatomic) NSCachedURLResponse *willCacheResponse;
@property (nonatomic) NSHTTPURLResponse *response;
@property (nonatomic) NSMutableData *data;
@property (nonatomic) NSError *connectionError;

+ (void)setUp;
+ (void)tearDown;

- (BOOL)didLoadFromNetwork;
- (BOOL)didLoadFromCache;
- (BOOL)didGetResponse;
- (BOOL)didLoadData;
- (BOOL)didGetError;
- (BOOL)didCacheResponse;

- (void)reset;
- (void)loadRequest:(NSURLRequest *)request;
- (void)provideResponseWithStatus:(NSUInteger)status cacheControl:(NSString *)cacheControl date:(NSDate *)date dataChunks:(NSArray *)dataChunks;
- (void)provideResponseWithStatus:(NSUInteger)status cacheControl:(NSString *)cacheControl date:(NSDate *)date;
- (void)provideBasicUncacheableResponse;
- (void)provideBasicCacheableResponse;
- (void)provideErrorResponse;

@end

// Request helper that uses NSURLConnection to issue requests.
@interface SPDYURLConnectionIntegrationTestHelper : SPDYIntegrationTestHelper<NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@end

// Request helper that uses NSURLSession (data task) to issue requests.
@interface SPDYURLSessionIntegrationTestHelper : SPDYIntegrationTestHelper<NSURLSessionDataDelegate>
@property (nonatomic) id<SPDYProtocolContext> spdyContext;
@end


