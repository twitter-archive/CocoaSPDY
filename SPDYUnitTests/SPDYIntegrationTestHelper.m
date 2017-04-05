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

#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYIntegrationTestHelper.h"
#import "SPDYMockSessionManager.h"
#import "SPDYProtocol.h"
#import "SPDYStream.h"

#pragma mark Base implementation

@implementation SPDYIntegrationTestHelper
{
    CFRunLoopRef _runLoop;
}

+ (void)setUp
{
    [SPDYMockSessionManager performSwizzling:YES];
}

+ (void)tearDown
{
    [SPDYMockSessionManager performSwizzling:NO];
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        [self provideErrorResponse];
    }
    return self;
}

- (BOOL)didLoadFromNetwork
{
    return self.didGetResponse && self.didLoadData && _stream != nil;
}

- (BOOL)didLoadFromCache
{
    return self.didGetResponse && self.didLoadData && _stream == nil;
}

- (BOOL)didGetResponse
{
    return _response != nil;
}

- (BOOL)didLoadData
{
    return _data.length > 0;
}

- (BOOL)didGetError
{
    return _connectionError != nil;
}

- (BOOL)didCacheResponse
{
    return _willCacheResponse != nil;
}

- (void)reset
{
    _stream = nil;
    _response = nil;
    _data = nil;
    _willCacheResponse = nil;
    _connectionError = nil;
}

- (void)loadRequest:(NSURLRequest *)request
{
    [self reset];

    // Needs to be implemented by subclass as well
}

- (NSString *)dateHeaderValue:(NSDate *)date
{
    NSString *string = nil;
    if (date) {
        time_t timeRaw = (long)date.timeIntervalSince1970;
        struct tm timeStruct;
        char buffer[80];

        gmtime_r(&timeRaw, &timeStruct);
        size_t charCount = strftime(buffer, sizeof(buffer), "%a, %d %b %Y %H:%M:%S GMT", &timeStruct);
        if (0 != charCount) {
            string = [[NSString alloc] initWithCString:buffer encoding:NSASCIIStringEncoding];
        }
    }

    return string;
}

- (void)provideResponseWithStatus:(NSUInteger)status cacheControl:(NSString *)cacheControl date:(NSDate *)date dataChunks:(NSArray *)dataChunks
{
    [SPDYMockSessionManager shared].streamQueuedBlock = ^(SPDYStream *stream) {
        _stream = stream;
        NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:@{
                @":status": [@(status) stringValue],
                @":version": @"1.1",
                }];
        if (date != nil) {
            headers[@"Date"] = [self dateHeaderValue:date];
        }
        if (cacheControl.length > 0) {
            headers[@"Cache-Control"] = cacheControl;
        }

        [stream mergeHeaders:headers];
        [stream didReceiveResponse];
        for (NSData *data in dataChunks) {
            [stream didLoadData:data];
        }
    };
}

- (void)provideResponseWithStatus:(NSUInteger)status cacheControl:(NSString *)cacheControl date:(NSDate *)date
{
    uint8_t dataBytes[] = {1};
    NSArray *dataChunks = @[ [NSData dataWithBytes:dataBytes length:1] ];
    [self provideResponseWithStatus:status cacheControl:cacheControl date:date dataChunks:dataChunks];
}

- (void)provideBasicUncacheableResponse
{
    [self provideResponseWithStatus:200 cacheControl:@"no-store, no-cache, must-revalidate" date:[NSDate date]];
}

- (void)provideBasicCacheableResponse
{
    [self provideResponseWithStatus:200 cacheControl:@"public, max-age=1200" date:[NSDate date]];
}

- (void)provideErrorResponse
{
    [SPDYMockSessionManager shared].streamQueuedBlock = ^(SPDYStream *stream) {
        _stream = stream;
        [stream closeWithError:[NSError errorWithDomain:@"SPDYUnitTest" code:1ul userInfo:nil]];
    };
}

- (void)_waitForRequestToFinish
{
    _runLoop = CFRunLoopGetCurrent();
    CFRunLoopRun();
}

- (void)_finishRequest
{
    CFRunLoopStop(_runLoop);
}

- (NSString *)description
{
    NSDictionary *params = @{
                             @"didLoadFromNetwork": @([self didLoadFromNetwork]),
                             @"didGetResponse": @([self didGetResponse]),
                             @"didLoadData": @([self didLoadData]),
                             @"didGetError": @([self didGetError]),
                             @"didCacheResponse": @([self didCacheResponse]),
                             @"stream": _stream ?: @"<nil>",
                             @"response": _response ?: @"<nil>",
                             @"willCacheResponse": _willCacheResponse ?: @"<nil>",
                             @"connectionError": _connectionError ?: @"<nil>",
                             };
    return [NSString stringWithFormat:@"<%@: %p> %@", [self class], self, params];
}

@end


#pragma mark NSURLConnection

@implementation SPDYURLConnectionIntegrationTestHelper

- (void)loadRequest:(NSURLRequest *)request
{
    [super loadRequest:request];

    [NSURLConnection connectionWithRequest:request delegate:self];

    [self _waitForRequestToFinish];
}

#pragma mark NSURLConnection delegate methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.response = (NSHTTPURLResponse *)response;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (self.data == nil) {
        self.data = [NSMutableData dataWithData:data];
    } else {
        [self.data appendData:data];
    }
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    self.willCacheResponse = cachedResponse;
    return cachedResponse;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    self.connectionError = nil;
    [self _finishRequest];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    self.connectionError = error;
    [self _finishRequest];
}

@end


#pragma mark NSURLSession

@implementation SPDYURLSessionIntegrationTestHelper
{
    NSURLCache *_cache;
    NSURLSessionConfiguration *_configuration;
    NSURLSession *_session;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _cache = [[NSURLCache alloc] initWithMemoryCapacity:1000000 diskCapacity:10000000 diskPath:nil];
    }
    return self;
}

- (void)loadRequest:(NSMutableURLRequest *)request
{
    [super loadRequest:request];

    _configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    _configuration.URLCache = _cache;
    _configuration.protocolClasses = @[ [SPDYURLSessionProtocol class] ];

    // request cache policy should be set in the NSURLSessionConfiguration, not in the request.
    // doing that here to simplify the tests.
    _configuration.requestCachePolicy = request.cachePolicy;

    _session = [NSURLSession sessionWithConfiguration:_configuration delegate:self delegateQueue:nil];

    // Special SPDY hack to get access to the NSURLSessionConfiguration
    request.SPDYURLSession = _session;

    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
    [task resume];

    [self _waitForRequestToFinish];
}

#pragma mark NSURLSession delegate methods

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    self.response = (NSHTTPURLResponse *)response;
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    if (self.data == nil) {
        self.data = [NSMutableData dataWithData:data];
    } else {
        [self.data appendData:data];
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse * cachedResponse))completionHandler
{
    self.willCacheResponse = proposedResponse;
    completionHandler(proposedResponse);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    // error may be nil
    self.connectionError = error;
    [self _finishRequest];
}

#pragma mark SPDYURLSessionDelegate methods

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didStartLoadingRequest:(NSURLRequest *)request withContext:(id<SPDYProtocolContext>)context
{
    self.spdyContext = context;
}

@end
