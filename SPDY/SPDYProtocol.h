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
#import "SPDYLogger.h"

extern NSString *const SPDYOriginRegisteredNotification;
extern NSString *const SPDYOriginUnregisteredNotification;

@class SPDYConfiguration;

@protocol SPDYTLSTrustEvaluator;

typedef enum {
    SPDYProxyStatusNone = 0,        // direct connection
    SPDYProxyStatusManual,          // manually configured HTTPS proxy
    SPDYProxyStatusManualInvalid,   // manually configured proxy but not supported
    SPDYProxyStatusManualWithAuth,  // manually configured HTTPS proxy that needs auth
    SPDYProxyStatusAuto,            // proxy auto-config URL, resolved to 1 or more HTTPS proxies
    SPDYProxyStatusAutoInvalid,     // proxy auto-config URL, did not resolve to supported HTTPS proxy
    SPDYProxyStatusAutoWithAuth,    // proxy auto-config URL, resolved to 1 or more HTTPS proxies needing auth
    SPDYProxyStatusConfig,          // info provided in SPDYConfiguration, not from system
    SPDYProxyStatusConfigWithAuth   // info provided in SPDYConfiguration, proxy needs auth
} SPDYProxyStatus;

@interface SPDYMetadata : NSObject

// SPDY stream time spent blocked - while queued waiting for connection, flow control, etc.
@property (nonatomic) NSUInteger blockedMs;

// Boolean indicating whether session is over cellular or WIFI
@property (nonatomic) BOOL cellular;

// SPDY stream creation time relative to session connection time.
@property (nonatomic) NSUInteger connectedMs;

// IP address of remote side
@property (nonatomic, copy) NSString *hostAddress;

// TCP port of remote side
@property (nonatomic) NSUInteger hostPort;

// SPDY session latency, in milliseconds, as measured by pings, e.g. "150". Default -1.
@property (nonatomic) NSInteger latencyMs;

// Indicates state of proxy configuration
@property (nonatomic) SPDYProxyStatus proxyStatus;

// SPDY stream bytes received. Includes all SPDY headers and bodies.
@property (nonatomic) NSUInteger rxBytes;

// SPDY stream bytes transmitted. Includes all SPDY headers and bodies.
@property (nonatomic) NSUInteger txBytes;

// SPDY request stream id, e.g. "1"
@property (nonatomic) NSUInteger streamId;

// SPDY version, e.g. "3.1"
@property (nonatomic, copy) NSString *version;

// Indicates connection used a proxy server
@property (nonatomic) BOOL viaProxy;

@end

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
  Current logger reference.
*/
+ (id<SPDYLogger>)currentLogger;

/**
  Set minimum logging level.
*/
+ (void)setLoggerLevel:(SPDYLogLevel)level;

/**
  Current logging level.
*/
+ (SPDYLogLevel)currentLoggerLevel;

/**
  Register an object to perform additional evaluation of TLS certificates.

  Methods on this object will be called from socket threads and should,
  therefore, be threadsafe.
*/
+ (void)setTLSTrustEvaluator:(id<SPDYTLSTrustEvaluator>)evaluator;

/**
  Internal hook for evaluating server trust.
*/
+ (bool)evaluateServerTrust:(SecTrustRef)trust forHost:(NSString *)host;

/*
  Retrieve the SPDY metadata from the response returned in connection:didReceiveResponse.
  Should be called during the connectionDidFinishLoading callback only, and use at any other
  time is undefined. Returns nil if response is nil or no metadata is available.
*/
+ (SPDYMetadata *)metadataForResponse:(NSURLResponse *)response;

/*
  Retrieve the SPDY metadata from the error returned in connection:didFailWithError. Should be
  called during that callback only, and use at any other time is undefined. Returns nil if error is
  nil or no metadata is available.
 */
+ (SPDYMetadata *)metadataForError:(NSError *)error;

/**
  Register an alias for the specified origin.

  Requests to the alias that would be handled by SPDY will be dispatched
  to a SPDY session opened to the aliased origin. The original host header
  will be preserved on the request.
*/
+ (void)registerAlias:(NSString *)aliasString forOrigin:(NSString *)originString;

/**
  Unregister an origin alias.
*/
+ (void)unregisterAlias:(NSString *)aliasString;

/**
  Unregister all origin aliases.
*/
+ (void)unregisterAllAliases;

@end

/**
  Protocol implementation intended for use with NSURLSession.

  Currently identical to SPDYProtocol, but potential future
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
+ (void)unregisterAllOrigins;

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

/**
  Enable or disable system-configured HTTPS proxy support.

  Default value is YES. Configuration of this option is experimental and
  may be removed in a future version.
*/
@property BOOL enableProxy;

/**
  Set HTTPS proxy host override.

  Default value is nil. If set in conjunction with proxyPort, overrides
  the system-configured proxy information and forces use of a proxy.
*/
@property NSString *proxyHost;

/**
  Set HTTPS proxy port override.

  Default value is 0. If set in conjunction with proxyHost, overrides
  the system-configured proxy information and forces use of a proxy.
*/
@property NSInteger proxyPort;

@end
