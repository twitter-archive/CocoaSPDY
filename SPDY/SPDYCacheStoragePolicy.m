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

typedef struct _HTTPTimeFormatInfo {
    const char *readFormat;
    const char *writeFormat;
    BOOL usesHasTimezoneInfo;
} HTTPTimeFormatInfo;

static HTTPTimeFormatInfo kTimeFormatInfos[] =
{
    { "%a, %d %b %Y %H:%M:%S %Z", "%a, %d %b %Y %H:%M:%S GMT", YES }, // Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
    { "%A, %d-%b-%y %H:%M:%S %Z", "%A, %d-%b-%y %H:%M:%S GMT", YES }, // Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
    { "%a %b %e %H:%M:%S %Y", "%a %b %e %H:%M:%S %Y", NO },           // Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
};


static NSDate *HTTPDateFromString(NSString *string)
{
    NSDate *date = nil;
    if (string) {
        struct tm parsedTime;
        const char *utf8String = [string UTF8String];

        for (int format = 0; (size_t)format < (sizeof(kTimeFormatInfos) / sizeof(kTimeFormatInfos[0])); format++) {
            HTTPTimeFormatInfo info = kTimeFormatInfos[format];
            if (info.readFormat != NULL && strptime(utf8String, info.readFormat, &parsedTime)) {
                NSTimeInterval ti = (info.usesHasTimezoneInfo ? mktime(&parsedTime) : timegm(&parsedTime));
                date = [NSDate dateWithTimeIntervalSince1970:ti];
                if (date) {
                    break;
                }
            }
        }
    }

    return date;
}

NSDictionary *HTTPCacheControlParameters(NSString *cacheControl)
{
    if (cacheControl.length == 0) {
        return nil;
    }

    NSArray *components = [cacheControl componentsSeparatedByString:@","];
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithCapacity:components.count];
    for (NSString *component in components) {
        NSArray *pair = [component componentsSeparatedByString:@"="];
        NSString *key = [pair[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *value = pair.count == 2 ? [pair[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
        parameters[key] = value;
    }
    return parameters;
}

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

    // Let's only cache GET requests
    if (cacheable) {
        if (![request.HTTPMethod isEqualToString:@"GET"]) {
            cacheable = NO;
        }
    }

    // If the response might be cacheable, look at the "Cache-Control" header in 
    // the response.

    // IMPORTANT: We can't rely on -rangeOfString: returning valid results if the target 
    // string is nil, so we have to explicitly test for nil in the following two cases.

    if (cacheable) {
        NSString *cacheResponseHeader;
        NSString *dateResponseHeader;

        for (NSString *key in [response.allHeaderFields allKeys]) {
            if ([key caseInsensitiveCompare:@"cache-control"] == NSOrderedSame) {
                cacheResponseHeader = [response.allHeaderFields[key] lowercaseString];
            }
            else if ([key caseInsensitiveCompare:@"date"] == NSOrderedSame) {
                dateResponseHeader = [response.allHeaderFields[key] lowercaseString];
            }
        }

        if (cacheResponseHeader != nil && [cacheResponseHeader rangeOfString:@"no-store"].location != NSNotFound) {
            cacheable = NO;
        }

        // Must have a Date header. Can't validate freshness otherwise.
        if (dateResponseHeader == nil) {
            cacheable = NO;
        }
    }

    // If we still think it might be cacheable, look at the "Cache-Control" header in 
    // the request. Also rule out requests with Authorization in them.

    if (cacheable) {
        NSString *requestHeader;

        requestHeader = [[request valueForHTTPHeaderField:@"cache-control"] lowercaseString];
        if ((requestHeader != nil && [requestHeader rangeOfString:@"no-store"].location != NSNotFound) ||
            [request valueForHTTPHeaderField:@"authorization"].length > 0) {
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

extern SPDYCachedResponseState SPDYCacheLoadingPolicy(NSURLRequest *request, NSCachedURLResponse *response)
{
    if (request == nil || response == nil) {
        return SPDYCachedResponseStateInvalid;
    }

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response.response;
    NSString *responseCacheControl;
    NSDate *responseDate;

    // Cached response validation

    // Get header values
    for (NSString *key in [httpResponse.allHeaderFields allKeys]) {
        if ([key caseInsensitiveCompare:@"cache-control"] == NSOrderedSame) {
            responseCacheControl = [httpResponse.allHeaderFields[key] lowercaseString];
        }
        else if ([key caseInsensitiveCompare:@"date"] == NSOrderedSame) {
            NSString *dateString = httpResponse.allHeaderFields[key];
            responseDate = HTTPDateFromString(dateString);
        }
    }

    if (responseCacheControl == nil || responseDate == nil) {
        return SPDYCachedResponseStateMustRevalidate;
    }

    if ([responseCacheControl rangeOfString:@"no-cache"].location != NSNotFound ||
        [responseCacheControl rangeOfString:@"must-revalidate"].location != NSNotFound ||
        [responseCacheControl rangeOfString:@"max-age=0"].location != NSNotFound) {
        return SPDYCachedResponseStateMustRevalidate;
    }

    // Verify item has not expired
    NSDictionary *cacheControlParams = HTTPCacheControlParameters(responseCacheControl);
    if (cacheControlParams[@"max-age"] != nil) {
        NSTimeInterval ageOfResponse = [[NSDate date] timeIntervalSinceDate:responseDate];
        NSTimeInterval maxAge = [cacheControlParams[@"max-age"] doubleValue];
        if (ageOfResponse > maxAge) {
            return SPDYCachedResponseStateMustRevalidate;
        }
    } else {
        // If no max-age, you have to revalidate
        return SPDYCachedResponseStateMustRevalidate;
    }

    // Request validation

    NSString *requestCacheControl = [[request valueForHTTPHeaderField:@"cache-control"] lowercaseString];

    if (requestCacheControl != nil) {
        if ([requestCacheControl rangeOfString:@"no-cache"].location != NSNotFound) {
            return SPDYCachedResponseStateMustRevalidate;
        }
    }

    // Note: there's a lot more validation we should do, to be a well-behaving user agent.
    // We don't support Pragma header.
    // We don't support Expires header.
    // We don't support Vary header.
    // We don't support ETag response header or If-None-Match request header.
    // We don't support Last-Modified response header or If-Modified-Since request header.
    // We don't look at more of the Cache-Control parameters, including ones that specify a field name.
    // ...

    return SPDYCachedResponseStateValid;
}