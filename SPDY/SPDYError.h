//
//  SPDYError.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXTERN NSString *const SPDYStreamErrorDomain;
FOUNDATION_EXTERN NSString *const SPDYSessionErrorDomain;
FOUNDATION_EXTERN NSString *const SPDYCodecErrorDomain;
FOUNDATION_EXTERN NSString *const SPDYSocketErrorDomain;

// These errors map one-to-one with the status code in a RST_STREAM message.
typedef enum {
    SPDYStreamProtocolError = 1,
    SPDYStreamInvalidStream,
    SPDYStreamRefusedStream,
    SPDYStreamUnsupportedVersion,
    SPDYStreamCancel,
    SPDYStreamInternalError,
    SPDYStreamFlowControlError,
    SPDYStreamStreamInUse,
    SPDYStreamStreamAlreadyClosed,
    SPDYStreamInvalidCredentials,
    SPDYStreamFrameTooLarge
} SPDYStreamError;

// These errors map one-to-one with the status code in a GOAWAY message.
typedef enum {
    SPDYSessionProtocolError = 1,
    SPDYSessionInternalError
} SPDYSessionError;

typedef enum {
    SPDYHeaderBlockEncodingError = 1,
    SPDYHeaderBlockDecodingError
} SPDYCodecError;

typedef enum {
    SPDYSocketCFSocketError = kCFSocketError, // From CFSocketError enum.
    SPDYSocketConnectCanceled = 1,            // socketWillConnect: returned NO.
    SPDYSocketConnectTimeout,
    SPDYSocketReadTimeout,
    SPDYSocketWriteTimeout,
    SPDYSocketTLSVerificationFailed,
    SPDYSocketTransportError,
    SPDYSocketProxyError
} SPDYSocketError;

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
