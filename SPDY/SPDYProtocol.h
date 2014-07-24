//
//  SPDYProtocol.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>

extern NSString *const SPDYOriginRegisteredNotification;
extern NSString *const SPDYOriginUnregisteredNotification;

@class SPDYConfiguration;

@protocol SPDYLogger;
@protocol SPDYTLSTrustEvaluator;

/**
  Client implementation of the SPDY/3.1 draft protocol.
*/
@interface SPDYProtocol : NSURLProtocol

/**
  Set configuration options to be used for all future SPDY sessions.
*/
+ (void)setConfiguration:(SPDYConfiguration *)configuration;

/**
  Copy of the current configuration in use by the protocol.
*/
+ (SPDYConfiguration *)currentConfiguration;

/**
  Register an object that implements @proto(SPDYLogger) to receive log
  output.

  Note that log messages are dispatched asynchronously.
 */
+ (void)setLogger:(id<SPDYLogger>)logger;

/**
  Register an object to perform additional evaluation of TLS certificates.

  Methods on this object will be called from socket threads and should,
  therefore, be threadsafe.
*/
+ (void)setTLSTrustEvaluator:(id<SPDYTLSTrustEvaluator>)evaluator;

/**
  Accessor for current TLS trust evaluation object.
*/
+ (id<SPDYTLSTrustEvaluator>)sharedTLSTrustEvaluator;

@end

/**
  Protocol implementation intended for use with NSURLSession.

  Currently identical to SDPYProtocol, but potential future
  NSURLSession-specific features will be present in this subclass only
*/
@interface SPDYURLSessionProtocol : SPDYProtocol
@end


/**
  Protocol implementation intended for use with NSURLConnection.
*/
@interface SPDYURLConnectionProtocol : SPDYProtocol

/**
  Register an endpoint with SPDY. The protocol will handle all future
  communication for that endpoint originating in the NSURL stack.

  @param origin The scheme-host-port tuple for the endpoint, in URL
  format, e.g. @"https://twitter.com:443"
 */
+ (void)registerOrigin:(NSString *)origin;

/**
  Unregister an endpoint with SPDY. The protocol will stop handling
  communication for the endpoint, though existing connections will be
  maintained until completion/termination.

  @param origin The scheme-host-port tuple for the endpoint, in URL
  format, e.g. @"https://twitter.com:443"
 */
+ (void)unregisterOrigin:(NSString *)origin;

/**
  Unregister all endpoints from SPDY. The protocol will stop handling
  any communication, though existing connections will be maintained
  until completion/termination.
 */
+ (void)unregisterAll;

@end

/**
  Configuration options for a SPDYSession.

  When a SPDY session is opened, a copy of the configuration object
  is made - you cannot modify the configuration of a session after it
  has been opened.
*/
@interface SPDYConfiguration : NSObject <NSCopying>

+ (SPDYConfiguration *)defaultConfiguration;

/**
  The number of parallel TCP connections to open to a single origin.

  Default is 1. It is STRONGLY recommended that you do not set this
  higher than 2. Configuration of this option is experimental and
  may be removed in a future version.
*/
@property NSUInteger sessionPoolSize;

/**
  Initial session window size for client flow control.

  Default is 10MB. If your application is receiving large responses and
  has ample memory available, it won't hurt to make this even larger.
*/
@property NSUInteger sessionReceiveWindow;

/**
  Initial stream window size for client flow control.

  Default is 10MB.
*/
@property NSUInteger streamReceiveWindow;

/**
  ZLib compression level to use for headers.

  Default is 9, which is appropriate for most cases. To disable header
  compression set this to 0.
*/
@property NSUInteger headerCompressionLevel;

/**
  Enable or disable sending minor protocol version with settings id 0.

  Default is enabled.
*/
@property BOOL enableSettingsMinorVersion;

/**
  TLS settings for the underlying CFSocketStream. Possible keys and
  values for TLS settings can be found in CFSocketStream.h

  Default is no settings.
*/
@property NSDictionary *tlsSettings;

/**
  Set timeout for creating a socket (TCP handshake).

  Default value is 60.0s. A negative value disables the timeout.
 */
@property NSTimeInterval connectTimeout;

/**
  Enable or disable TCP_NODELAY.

  Default value is NO. Configuration of this option is experimental and
  may be removed in a future version.
 */
@property BOOL enableTCPNoDelay;

@end
