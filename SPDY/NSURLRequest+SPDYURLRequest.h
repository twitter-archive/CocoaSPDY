//
//  NSURLRequest+SPDYURLRequest.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>

@interface NSURLRequest (SPDYURLRequest)

/**
  If present, the stream specified will be used as the HTTP body for the
  request. This circumvents a bug in CFNetwork with HTTPBodyStream, but will
  not allow a stream to be replayed in the event of an authentication
  challenge or redirect. If either of those responses is a possibility, use
  HTTPBody or SPDYBodyFile instead.
*/
@property (nonatomic, readonly) NSInputStream *SPDYBodyStream;

/**
  If present, the file path specified will be used as the HTTP body for the
  request. This is the preferred secondary mechanism for specifying the body
  of a request when HTTPBody is not sufficient.
*/
@property (nonatomic, readonly) NSString *SPDYBodyFile;

/**
  Priority per the SPDY draft spec. Defaults to 0.
*/
@property (nonatomic, readonly) NSUInteger SPDYPriority;

/**
  Specifies whether this request may be deferred until an active session is
  available. Defaults to false.
*/
@property (nonatomic, readonly) BOOL SPDYDiscretionary;

/**
  Request header fields canonicalized to SPDY format.
*/
- (NSDictionary *)allSPDYHeaderFields;
@end

@interface NSMutableURLRequest (SPDYURLRequest)
@property (nonatomic) NSInputStream *SPDYBodyStream;
@property (nonatomic) NSString *SPDYBodyFile;
@property (nonatomic) NSUInteger SPDYPriority;
@property (nonatomic) BOOL SPDYDiscretionary;
@end
