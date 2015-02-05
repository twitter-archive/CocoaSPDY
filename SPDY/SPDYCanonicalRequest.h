//
//  SPDYCanonicalRequest.h
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

#import <Foundation/Foundation.h>

/*
    The Foundation URL loading system needs to be able to canonicalize URL requests 
    for various reasons (for example, to look for cache hits).  The default HTTP/HTTPS 
    protocol has a complex chunk of code to perform this function.  Unfortunately 
    there's no way for third party code to access this.  Instead, we have to reimplement 
    it all ourselves.  This is split off into a separate file to emphasise that this 
    is standard boilerplate that you probably don't need to look at.
    
    IMPORTANT: While you can take most of this code as read, you might want to tweak 
    the handling of the "Accept-Language" in the CanonicaliseHeaders routine.
*/

extern NSMutableURLRequest *SPDYCanonicalRequestForRequest(NSURLRequest *request);
