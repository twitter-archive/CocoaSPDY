//
//  SPDYCacheStoragePolicy.h
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

#include <Foundation/Foundation.h>

/*! Determines the cache storage policy for a response.
 *  \details When we provide a response up to the client we need to tell the client whether
 *  the response is cacheable or not.  The default HTTP/HTTPS protocol has a reasonable
 *  complex chunk of code to determine this, but we can't get at it.  Thus, we have to
 *  reimplement it ourselves.  This is split off into a separate file to emphasise that
 *  this is standard boilerplate that you probably don't need to look at.
 *  \param request The request that generated the response; must not be nil.
 *  \param response The response itself; must not be nil.
 *  \returns A cache storage policy to use.
 */
extern NSURLCacheStoragePolicy SPDYCacheStoragePolicy(NSURLRequest *request, NSHTTPURLResponse *response);

typedef enum {
    SPDYCachedResponseStateValid = 0,
    SPDYCachedResponseStateInvalid,
    SPDYCachedResponseStateMustRevalidate
} SPDYCachedResponseState;

/*! Determines the validity of a cached response 
 */
extern SPDYCachedResponseState SPDYCacheLoadingPolicy(NSURLRequest *request, NSCachedURLResponse *response);
