//
//  SPDYMockURLProtocolClient.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import "SPDYMockURLProtocolClient.h"

@implementation SPDYMockURLProtocolClient

- (void)URLProtocol:(NSURLProtocol *)urlProtocol wasRedirectedToRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
    _calledWasRedirectedToRequest++; 
    _lastRedirectedRequest = request;
    _lastRedirectResponse = redirectResponse;
}

- (void)URLProtocol:(NSURLProtocol *)urlProtocol cachedResponseIsValid:(NSCachedURLResponse *)cachedResponse
{
    _calledCachedResponseIsValid++;
    _lastCachedResponse = cachedResponse;
}

- (void)URLProtocol:(NSURLProtocol *)urlProtocol didReceiveResponse:(NSURLResponse *)response cacheStoragePolicy:(NSURLCacheStoragePolicy)policy
{
    _calledDidReceiveResponse++;
    _lastResponse = response;
    _lastCacheStoragePolicy = policy;
}

- (void)URLProtocol:(NSURLProtocol *)urlProtocol didLoadData:(NSData *)data
{
    _calledDidLoadData++;
    _lastData = data;
}

- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)urlProtocol
{
    _calledDidFinishLoading++;
}

- (void)URLProtocol:(NSURLProtocol *)urlProtocol didFailWithError:(NSError *)error
{
    _calledDidFailWithError++;
    _lastError = error;
}

- (void)URLProtocol:(NSURLProtocol *)urlProtocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    _calledDidReceiveAuthenticationChallenge++;
    _lastReceivedAuthenticationChallenge = challenge;
}

- (void)URLProtocol:(NSURLProtocol *)urlProtocol didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    _calledDidCancelAuthenticationChallenge++;
    _lastCanceledAuthenticationChallenge = challenge;
}

@end

