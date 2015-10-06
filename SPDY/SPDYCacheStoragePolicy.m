//
//  SPDYCacheStoragePolicy.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Derived from code in Apple, Inc.'s CustomHTTPProtocol sample
//  project, found as of this notice at
//  https://developer.apple.com/LIBRARY/IOS/samplecode/CustomHTTPProtocol
//

#import "SPDYCacheStoragePolicy.h"

extern NSURLCacheStoragePolicy SPDYCacheStoragePolicy(NSURLRequest *request, NSHTTPURLResponse *response)
{
    bool                     cacheable;
    NSURLCacheStoragePolicy  result;

    // First determine if the request is cacheable based on its status code.
    
    switch (response.statusCode) {
        case 200:
        case 203:
        case 206:
        case 301:
        case 304:
        case 404:
        case 410:
            cacheable = YES;
            break;
        default:
            cacheable = NO;
            break;
    }

    // If the response might be cacheable, look at the "Cache-Control" header in 
    // the response.

    // IMPORTANT: We can't rely on -rangeOfString: returning valid results if the target 
    // string is nil, so we have to explicitly test for nil in the following two cases.

    if (cacheable) {
        NSString *responseHeader;

        for (NSString *key in [response.allHeaderFields allKeys]) {
            if ([key caseInsensitiveCompare:@"cache-control"] == NSOrderedSame) {
                responseHeader = [response.allHeaderFields[key] lowercaseString];
                break;
            }
        }

        if (responseHeader != nil && [responseHeader rangeOfString:@"no-store"].location != NSNotFound) {
            cacheable = NO;
        }
    }

    // If we still think it might be cacheable, look at the "Cache-Control" header in 
    // the request.

    if (cacheable) {
        NSString *requestHeader;

        requestHeader = [[request valueForHTTPHeaderField:@"cache-control"] lowercaseString];
        if (requestHeader != nil                                             &&
            [requestHeader rangeOfString:@"no-store"].location != NSNotFound &&
            [requestHeader rangeOfString:@"no-cache"].location != NSNotFound) {
            cacheable = NO;
        }
    }

    // Use the cacheable flag to determine the result.
    
    if (cacheable) {
        // Modern versions of iOS use file protection to protect the cache, and thus are
        // happy to cache HTTPS on disk. Previous code here returned
        // NSURLCacheStorageAllowedInMemoryOnly for https.
        result = NSURLCacheStorageAllowed;
    } else {
        result = NSURLCacheStorageNotAllowed;
    }

    return result;
}
