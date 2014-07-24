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

extern NSString *const SPDYStreamErrorDomain;
extern NSString *const SPDYSessionErrorDomain;
extern NSString *const SPDYCodecErrorDomain;
extern NSString *const SPDYSocketErrorDomain;

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
    SDPYHeaderBlockEncodingError = 1,
    SDPYHeaderBlockDecodingError
} SPDYCodecError;

typedef enum {
    SPDYSocketCFSocketError = kCFSocketError, // From CFSocketError enum.
    SPDYSocketConnectCanceled = 1,            // socketWillConnect: returned NO.
    SPDYSocketConnectTimeout,
    SPDYSocketReadTimeout,
    SPDYSocketWriteTimeout,
    SPDYSocketTLSVerificationFailed,
    SPDYSocketTransportError
} SPDYSocketError;

#define SPDY_STREAM_ERROR(CODE, MESSAGE) \
    [[NSError alloc] initWithDomain:SPDYStreamErrorDomain code:CODE userInfo:@{ NSLocalizedDescriptionKey: MESSAGE}]

#define SPDY_SESSION_ERROR(CODE, MESSAGE) \
    [[NSError alloc] initWithDomain:SPDYSessionErrorDomain code:CODE userInfo:@{ NSLocalizedDescriptionKey: MESSAGE}]

#define SPDY_SOCKET_ERROR(CODE, MESSAGE) \
    [[NSError alloc] initWithDomain:SPDYSocketErrorDomain code:CODE userInfo:@{ NSLocalizedDescriptionKey: MESSAGE}]

#define SPDY_CODEC_ERROR(CODE, MESSAGE) \
    [[NSError alloc] initWithDomain:SPDYCodecErrorDomain code:CODE userInfo:@{ NSLocalizedDescriptionKey: MESSAGE}]
