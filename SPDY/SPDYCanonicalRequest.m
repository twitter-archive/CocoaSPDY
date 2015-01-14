//
//  SPDYCanonicalRequest.m
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

#import <sys/utsname.h>
#import "SPDYCanonicalRequest.h"
#import "NSURLRequest+SPDYURLRequest.h"

#include <xlocale.h>

static dispatch_once_t __defaultUserAgentInitialized;
static NSString *__defaultUserAgent;

static NSString *getDefaultUserAgent()
{
    // NSURLConnection-based request example:
    //     <product-name>/<build-number> CFNetwork/548.0.3 Darwin/11.2.0
    //
    // UIWebView-based request example:
    //     Mozilla/5.0 (iPhone Simulator; CPU iPhone OS 5_0 like Mac OS X) AppleWebKit/534.46 (KHTML, like Gecko) Mobile/9A334
    //
    // We're going to mimic the NSURLConnection one.

    dispatch_once(&__defaultUserAgentInitialized, ^{
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *mainBundleName = [mainBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleNameKey];
        NSString *mainBundleVersion = [mainBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];

        NSBundle *cfnetworkBundle = [NSBundle bundleWithIdentifier:@"com.apple.CFNetwork"];
        NSString *cfnetworkName = [cfnetworkBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleNameKey];
        NSString *cfnetworkVersion = [cfnetworkBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];

        NSString *sysName = nil;
        NSString *sysVersion = nil;
        struct utsname name;
        if (uname(&name) == 0) {
            sysName = [NSString stringWithCString:name.sysname encoding:NSASCIIStringEncoding];
            sysVersion = [NSString stringWithCString:name.release encoding:NSASCIIStringEncoding];
        }

        NSString *userAgent;
        if (mainBundleName != nil) {
            if (mainBundleVersion != nil) {
                userAgent = [NSString stringWithFormat:@"%@/%@", mainBundleName, mainBundleVersion];
            } else {
                userAgent = mainBundleName;
            }
        } else {
            userAgent = @"CocoaSPDY/1.0";
        }

        if (cfnetworkName != nil && cfnetworkVersion != nil) {
            userAgent = [userAgent stringByAppendingFormat:@" %@/%@", cfnetworkName, cfnetworkVersion];
        }

        if (sysName != nil && sysVersion != nil) {
            userAgent = [userAgent stringByAppendingFormat:@" %@/%@", sysName, sysVersion];
        }

        __defaultUserAgent = userAgent;
    });

    return __defaultUserAgent;
}

#pragma mark * URL canonicalization steps

typedef CFIndex (*CanonicalRequestStepFunction)(NSURL *url, NSMutableData *urlData, CFIndex bytesInserted);

static CFIndex FixPostSchemeSeparator(NSURL *url, NSMutableData *urlData, CFIndex bytesInserted)
    // The separator after the scheme should be "://"; if that's not the case, fix it.
{
    CFRange     range;
    uint8_t *   urlDataBytes;
    NSUInteger  urlDataLength;
    NSUInteger  cursor;
    NSUInteger  separatorLength;
    NSUInteger  expectedSeparatorLength;

    assert(url != nil);
    assert(urlData != nil);
    assert(bytesInserted >= 0);

    range = CFURLGetByteRangeForComponent((__bridge CFURLRef)url, kCFURLComponentScheme, NULL);
    if (range.location != kCFNotFound) {
        assert(range.location >= 0);
        assert(range.length >= 0);

        urlDataBytes  = urlData.mutableBytes;
        urlDataLength = urlData.length;

        separatorLength = 0;
        cursor = (NSUInteger)range.location + (NSUInteger)bytesInserted + (NSUInteger)range.length;
        if ( (cursor < urlDataLength) && (urlDataBytes[cursor] == ':') ) {
            cursor += 1;
            separatorLength += 1;
            if ( (cursor < urlDataLength) && (urlDataBytes[cursor] == '/') ) {
                cursor += 1;
                separatorLength += 1;
                if ( (cursor < urlDataLength) && (urlDataBytes[cursor] == '/') ) {
                    cursor += 1;
                    separatorLength += 1;
                }
            }
        }
        #pragma unused(cursor)          // quietens an analyser warning

        expectedSeparatorLength = strlen("://");
        if (separatorLength != expectedSeparatorLength) {
            [urlData replaceBytesInRange:NSMakeRange((NSUInteger) range.location + (NSUInteger) bytesInserted + (NSUInteger) range.length, separatorLength) withBytes:"://" length:expectedSeparatorLength];
            bytesInserted = kCFNotFound;        // have to build everything now
        }
    }

    return bytesInserted;
}

static CFIndex LowercaseScheme(NSURL *url, NSMutableData *urlData, CFIndex bytesInserted)
    // The scheme should be lower case; if it's not, make it so.
{
    CFRange     range;
    uint8_t *   urlDataBytes;
    CFIndex     i;

    assert(url != nil);
    assert(urlData != nil);
    assert(bytesInserted >= 0);

    range = CFURLGetByteRangeForComponent((__bridge CFURLRef)url, kCFURLComponentScheme, NULL);
    if (range.location != kCFNotFound) {
        assert(range.location >= 0);
        assert(range.length >= 0);

        urlDataBytes = [urlData mutableBytes];
        for (i = range.location + bytesInserted; i < (range.location + bytesInserted + range.length); i++) {
            urlDataBytes[i] = (uint8_t) tolower_l(urlDataBytes[i], NULL);
        }
    }
    return bytesInserted;
}

static CFIndex LowercaseHost(NSURL *url, NSMutableData *urlData, CFIndex bytesInserted)
    // The host should be lower case; if it's not, make it so.
{
    CFRange     range;
    uint8_t *   urlDataBytes;
    CFIndex     i;

    assert(url != nil);
    assert(urlData != nil);
    assert(bytesInserted >= 0);

    range = CFURLGetByteRangeForComponent((__bridge CFURLRef)url, kCFURLComponentHost, NULL);
    if (range.location != kCFNotFound) {
        assert(range.location >= 0);
        assert(range.length >= 0);

        urlDataBytes = [urlData mutableBytes];
        for (i = range.location + bytesInserted; i < (range.location + bytesInserted + range.length); i++) {
            urlDataBytes[i] = (uint8_t) tolower_l(urlDataBytes[i], NULL);
        }
    }
    return bytesInserted;
}

static CFIndex FixEmptyHost(NSURL *url, NSMutableData *urlData, CFIndex bytesInserted)
    // An empty host should be treated as "localhost" case; if it's not, make it so.
{
    #pragma unused(urlData)
    CFRange     range;
    CFRange     rangeWithSeparator;

    assert(url != nil);
    assert(urlData != nil);
    assert(bytesInserted >= 0);

    range = CFURLGetByteRangeForComponent((__bridge CFURLRef)url, kCFURLComponentHost, &rangeWithSeparator);
    if (range.length == 0) {
        NSUInteger  localhostLength;

        assert(range.location >= 0);
        assert(range.length >= 0);

        localhostLength = strlen("localhost");
        if (range.location != kCFNotFound) {
            [urlData replaceBytesInRange:NSMakeRange( (NSUInteger) range.location + (NSUInteger) bytesInserted, 0) withBytes:"localhost" length:localhostLength];
            bytesInserted += localhostLength;
        } else if (rangeWithSeparator.location != kCFNotFound && rangeWithSeparator.length == 0) {
            [urlData replaceBytesInRange:NSMakeRange((NSUInteger) rangeWithSeparator.location + (NSUInteger) bytesInserted, 0) withBytes:"localhost" length:localhostLength];
            bytesInserted += localhostLength;
        }
    }
    return bytesInserted;
}

static CFIndex FixEmptyPath(NSURL *url, NSMutableData *urlData, CFIndex bytesInserted)
    // Transform an empty URL path to "/".  For example, "http://www.apple.com" becomes "http://www.apple.com/".
{
    #pragma unused(urlData)
    CFRange     range;
    CFRange     rangeWithSeparator;

    assert(url != nil);
    assert(urlData != nil);
    assert(bytesInserted >= 0);

    range = CFURLGetByteRangeForComponent((__bridge CFURLRef)url, kCFURLComponentPath, &rangeWithSeparator);
    // The following is not a typo.  We use rangeWithSeparator to find where to insert the
    // "/" and the range length to decide whether we /need/ to insert the "/".
    if (rangeWithSeparator.location != kCFNotFound && range.length == 0) {
        assert(range.location >= 0);
        assert(range.length >= 0);
        assert(rangeWithSeparator.location >= 0);
        assert(rangeWithSeparator.length >= 0);

        [urlData replaceBytesInRange:NSMakeRange( (NSUInteger) rangeWithSeparator.location + (NSUInteger) bytesInserted, 0) withBytes:"/" length:1];
        bytesInserted += 1;
    }
    return bytesInserted;
}

__attribute__((unavailable)) static CFIndex DeleteDefaultPort(NSURL *url, NSMutableData *urlData, CFIndex bytesInserted)
    // If the user specified the default port (80 for HTTP, 443 for HTTPS), remove it from the URL.

    // Actually this code is disabled because the equivalent code in the default protocol handle
    // has also been disabled; some setups depend on get the port number in the URL, even if it
    // is the default.
{
    NSString *  scheme;
    BOOL        isHTTP;
    BOOL        isHTTPS;
    CFRange     range;
    uint8_t *   urlDataBytes;
    NSString *  portNumberStr;
    int         portNumber;

    assert(url != nil);
    assert(urlData != nil);
    assert(bytesInserted >= 0);

    scheme = [url.scheme lowercaseString];
    assert(scheme != nil);

    isHTTP  = [scheme isEqual:@"http" ];
    isHTTPS = [scheme isEqual:@"https"];

    range = CFURLGetByteRangeForComponent((__bridge CFURLRef)url, kCFURLComponentPort, NULL);
    if (range.location != kCFNotFound) {
        assert(range.location >= 0);
        assert(range.length >= 0);

        urlDataBytes = [urlData mutableBytes];

        portNumberStr = [[NSString alloc] initWithBytes:&urlDataBytes[range.location + bytesInserted] length:(NSUInteger) range.length encoding:NSUTF8StringEncoding];
        if (portNumberStr != nil) {
            portNumber = [portNumberStr intValue];
            if ( (isHTTP && (portNumber == 80)) || (isHTTPS && (portNumber == 443)) ) {
                // -1 and +1 to account for the leading ":"
                [urlData replaceBytesInRange:NSMakeRange((NSUInteger) range.location + (NSUInteger) bytesInserted - 1, (NSUInteger) range.length + 1) withBytes:NULL length:0];
                bytesInserted -= (range.length + 1);
            }
        }
    }
    return bytesInserted;
}

#pragma mark * Other request canonicalization

static void CanonicaliseHeaders(NSMutableURLRequest * request)
    // Canonicalise the request headers.
{
    // If there's no content type and the request is a POST with a body, add a default
    // content type of "application/x-www-form-urlencoded".

    if ([request valueForHTTPHeaderField:@"Content-Type"] == nil
     && [request.HTTPMethod caseInsensitiveCompare:@"POST"] == NSOrderedSame
     && (request.HTTPBody != nil || request.HTTPBodyStream != nil
            || request.SPDYBodyFile != nil || request.SPDYBodyStream != nil)) {
        [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    }

    // If there's not "Accept" header, add a default.

    if ([request valueForHTTPHeaderField:@"Accept"] == nil) {
        [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    }

    // If there's not "Accept-Encoding" header, add a default.

    if ([request valueForHTTPHeaderField:@"Accept-Encoding"] == nil) {
        [request setValue:@"gzip, deflate" forHTTPHeaderField:@"Accept-Encoding"];
    }

    // If there's not an "Accept-Language" header, add a default.  This is quite bogus; ideally we
    // should derive the correct "Accept-Language" value from the langauge that the app is running
    // in.  However, that's quite difficult to get right, so rather than show some general purpose
    // code that might fail in some circumstances, I've decided to just hardwire US English.
    // If you use this code in your own app you can customise it as you see fit.  One option might be
    // to base this value on -[NSBundle preferredLocalizations], so that the web page comes back in
    // the language that the app is running in.

    if ([request valueForHTTPHeaderField:@"Accept-Language"] == nil) {
        [request setValue:@"en-us" forHTTPHeaderField:@"Accept-Language"];
    }

    // NSURLRequest will automatically set the content-length header when HTTPBody is used,
    // so we'll do that too. Note that when using HTTPBodyStream, the content-length is not
    // automatically set, so neither will we. Also note we pay no attention to the HTTP method.
    if ([request valueForHTTPHeaderField:@"Content-Length"] == nil) {
        int64_t contentLength = -1;
        if (request.HTTPBody) {
            contentLength = request.HTTPBody.length;
        } else if (request.SPDYBodyFile) {
            NSString *path = [request.SPDYBodyFile stringByResolvingSymlinksInPath];
            contentLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
        }

        if (contentLength >= 0) {
            [request setValue:[@(contentLength) stringValue] forHTTPHeaderField:@"Content-Length"];
        }
    }

    // Add a default user agent that matches what Apple's HTTP system will add. As we cannot
    // get the default directly, this is only approximate.
    if ([request valueForHTTPHeaderField:@"User-Agent"] == nil) {
        [request setValue:getDefaultUserAgent() forHTTPHeaderField:@"User-Agent"];
    }
}

#pragma mark * API

extern NSMutableURLRequest *SPDYCanonicalRequestForRequest(NSURLRequest *request)
{
    NSMutableURLRequest *   result;
    NSString *              scheme;

    result = [request mutableCopy];

    // First up check that we're dealing with HTTP or HTTPS.  If not, do nothing (why were we
    // we even called?).

    scheme = [request.URL.scheme lowercaseString];
    assert(scheme != nil);

    if (![scheme isEqual:@"http"] && ![scheme isEqual:@"https"]) {
        assert(NO);
    } else {
        CFIndex         bytesInserted;
        NSURL *         requestURL;
        NSMutableData * urlData;
        static const CanonicalRequestStepFunction kStepFunctions[] = {
            FixPostSchemeSeparator,
            LowercaseScheme,
            LowercaseHost,
            FixEmptyHost,
            // DeleteDefaultPort, -- The built-in canonicalizer has stopped doing this, so we don't do it either.
            FixEmptyPath
        };
        size_t          stepIndex;
        size_t          stepCount;

        // Canonicalise the URL by executing each of our step functions.

        bytesInserted = kCFNotFound;
        urlData = nil;
        requestURL = [request URL];
        assert(requestURL != nil);

        stepCount = sizeof(kStepFunctions) / sizeof(*kStepFunctions);
        for (stepIndex = 0; stepIndex < stepCount; stepIndex++) {

            // If we don't have valid URL data, create it from the URL.

            assert(requestURL != nil);
            if (bytesInserted == kCFNotFound) {
                NSData *    urlDataImmutable;

                urlDataImmutable = CFBridgingRelease(CFURLCreateData(NULL, (__bridge CFURLRef)requestURL, kCFStringEncodingUTF8, true));
                assert(urlDataImmutable != nil);

                urlData = [urlDataImmutable mutableCopy];
                assert(urlData != nil);

                bytesInserted = 0;
            }
            assert(urlData != nil);

            // Run the step.

            bytesInserted = kStepFunctions[stepIndex](requestURL, urlData, bytesInserted);

            // fprintf(stderr, "  [%zu] %.*s\n", stepIndex, (int) [urlData length], (const char *) [urlData bytes]);

            // If the step invalidated our URL (or we're on the last step, whereupon we'll need
            // the URL outside of the loop), recreate the URL from the URL data.

            if (bytesInserted == kCFNotFound || stepIndex + 1 == stepCount) {
                requestURL = CFBridgingRelease(CFURLCreateWithBytes(NULL, urlData.bytes, (CFIndex)urlData.length, kCFStringEncodingUTF8, NULL));
                assert(requestURL != nil);

                urlData = nil;
            }
        }

        [result setURL:requestURL];

        // Canonicalise the headers.

        CanonicaliseHeaders(result);
    }

    return result;
}
