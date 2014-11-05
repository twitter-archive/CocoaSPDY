//
//  SPDYMockURLProtocolClient.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <Foundation/Foundation.h>
#import "SPDYProtocol.h"

@interface SPDYMockURLProtocolClient : NSObject <NSURLProtocolClient>

@property(nonatomic) int calledWasRedirectedToRequest;
@property(nonatomic) int calledCachedResponseIsValid;
@property(nonatomic) int calledDidReceiveResponse;
@property(nonatomic) int calledDidLoadData;
@property(nonatomic) int calledDidFinishLoading;
@property(nonatomic) int calledDidFailWithError;
@property(nonatomic) int calledDidReceiveAuthenticationChallenge;
@property(nonatomic) int calledDidCancelAuthenticationChallenge;

@property(nonatomic, strong) NSURLRequest *lastRedirectedRequest;
@property(nonatomic, strong) NSURLResponse *lastRedirectResponse;
@property(nonatomic, strong) NSCachedURLResponse *lastCachedResponse;
@property(nonatomic, strong) NSURLResponse *lastResponse;
@property(nonatomic) NSURLCacheStoragePolicy lastCacheStoragePolicy;
@property(nonatomic, strong) NSData *lastData;
@property(nonatomic, strong) NSError *lastError;
@property(nonatomic, strong) NSURLAuthenticationChallenge *lastReceivedAuthenticationChallenge;
@property(nonatomic, strong) NSURLAuthenticationChallenge *lastCanceledAuthenticationChallenge;
@end

