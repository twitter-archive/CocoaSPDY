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

@protocol SPDYExtendedDelegate;

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
  If set to > 0, indicates the maximum time interval the request dispatch may
  be deferred to optimize battery/power usage for less time-sensitive
  requests.

  Note the request's idle timeoutInterval still applies and must be set large
  enough to allow for both a discretionary delay and normal request transit.
*/
@property (nonatomic, readonly) NSTimeInterval SPDYDeferrableInterval;

/**
  If set, SPDYProtocol will decline to handle the request and instead pass
  it along to the next registered protocol (e.g. NSHTTPURLProtocol).
*/
@property (nonatomic, readonly) BOOL SPDYBypass;

/**
  Contextual NSURLSession that was associated with this request. The application
  should set this if using NSURLSession to load the request in order to provide
  proper per-request configuration information, and if support for the
  extended SPDYURLSessionDelegate is desired.
 */
@property (nonatomic, readonly) NSURLSession *SPDYURLSession;

/**
  Request header fields canonicalized to SPDY format.
*/
- (NSDictionary *)allSPDYHeaderFields;

@end

@interface NSMutableURLRequest (SPDYURLRequest)
@property (nonatomic) NSInputStream *SPDYBodyStream;
@property (nonatomic) NSString *SPDYBodyFile;
@property (nonatomic) NSTimeInterval SPDYDeferrableInterval;
@property (nonatomic) NSUInteger SPDYPriority;
@property (nonatomic) BOOL SPDYBypass;
@property (nonatomic) NSURLSession *SPDYURLSession;
@end
