//
//  SPDYOrigin.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>

/**
 Representation for RFC 6454 origin.
 
 http://www.ietf.org/rfc/rfc6454.txt
 */
@interface SPDYOrigin : NSObject <NSCopying>
@property (nonatomic, readonly) NSString *scheme;
@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) in_port_t port;

- (id)initWithString:(NSString *)urlString error:(NSError **)pError;
- (id)initWithURL:(NSURL *)url error:(NSError **)pError;
- (id)initWithScheme:(NSString *)scheme
                host:(NSString *)host
                port:(in_port_t)port
               error:(NSError **)pError;
@end
