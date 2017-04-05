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
#include <time.h>
#include <xlocale.h>

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
        const char *utf8String = [string UTF8String];

        for (int format = 0; (size_t)format < (sizeof(kTimeFormatInfos) / sizeof(kTimeFormatInfos[0])); format++) {
            HTTPTimeFormatInfo info = kTimeFormatInfos[format];
            struct tm parsedTime = { 0 };
            if (info.readFormat != NULL && strptime_l(utf8String, info.readFormat, &parsedTime, NULL)) {
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

static NSString *GetKey(const char **ppStr) {
    const char *p = *ppStr;

    // Advance to next delimiter
    while (*p != '\0' && *p != '=' && *p != ',') {
        p++;
    }

    // No progress? Error.
    if (p == *ppStr) {
        return nil;
    }

    NSString *str = [[NSString alloc] initWithBytes:*ppStr length:(p - *ppStr) encoding:NSUTF8StringEncoding];
    *ppStr = p;
    return [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *GetValue(const char **ppStr) {
    // **ppStr, at input, should be null for EOS, "," for single token, or "=" for dual token.
    const char *p = *ppStr;

    // Single token with no value, EOS
    if (*p == '\0') {
        return @"";
    }

    // Single token with no value, more after
    if (*p == ',') {
        (*ppStr)++;
        return @"";
    }

    // Must be token with value, error if not
    if (*p != '=') {
        return nil;
    }

    // skip '='
    p++;
    (*ppStr)++;

    // Value is either a quoted string or a token
    NSString *str;
    if (*p == '"') {
        p++; // skip opening quote

        // Advance to delimiter, ignoring escaped quotes like '\"' in the string
        while (*p != '\0' && (*p != '"' || *(p-1) == '\\')) {
            p++;
        }

        // EOS before closing quote? Error.
        if (*p == '\0') {
            return nil;
        }

        p++; // skip closing quote

        // Don't trim whitespace from within quoted string
        str = [[NSString alloc] initWithBytes:(*ppStr + 1) length:(p - *ppStr - 2) encoding:NSUTF8StringEncoding];
    } else {
        // Advance to delimiter
        while (*p != '\0' && *p != ',') {
            p++;
        }

        // No progress? Error.
        if (p == *ppStr) {
            return nil;
        }

        str = [[[NSString alloc] initWithBytes:*ppStr length:(p - *ppStr) encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    // Skip trailing whitespace and trailing token delimiter
    while (*p != '\0' && (*p == ' ' || *p == ',')) {
        p++;
    }

    *ppStr = p;
    return str;
}

// Exposed only for tests
extern NSDictionary *HTTPCacheControlParameters(NSString *cacheControl)
{
    if (cacheControl.length == 0) {
        return nil;
    }

    const char *pStr = [cacheControl cStringUsingEncoding:NSUTF8StringEncoding];

    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];

    while (YES) {
        NSString *key = GetKey(&pStr);
        if (key.length == 0) {
            break;
        }
        NSString *value = GetValue(&pStr);
        if (value == nil) {
            break;
        }
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
    // the request.

    if (cacheable) {
        NSString *requestHeader;

        requestHeader = [[request valueForHTTPHeaderField:@"cache-control"] lowercaseString];
        if (requestHeader != nil && [requestHeader rangeOfString:@"no-store"].location != NSNotFound) {
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

    // Note: there's a lot more validation we should do, to be a well-behaving user agent. RFC7234
    // should be consulted.
    // We don't support Pragma header.
    // We don't support Expires header.
    // We don't support Vary header.
    // We don't support ETag response header or If-None-Match request header.
    // We don't support Last-Modified response header or If-Modified-Since request header.
    // We don't look at more of the Cache-Control parameters, including ones that specify a field name.
    // We need to generate the Age header in the cached response.
    // We need to invalidate the cached item if PUT,POST,DELETE request gets a successful response.
    // - including the item in Location header.
    // ...

    return SPDYCachedResponseStateValid;
}
