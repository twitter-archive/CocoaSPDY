//
//  SPDYSession.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import <netinet/in.h>
#import <netinet/tcp.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYCommonLogger.h"
#import "SPDYFrameDecoder.h"
#import "SPDYFrameEncoder.h"
#import "SPDYOrigin.h"
#import "SPDYProtocol.h"
#import "SPDYSession.h"
#import "SPDYSessionManager.h"
#import "SPDYSettingsStore.h"
#import "SPDYSocket.h"
#import "SPDYStream.h"
#import "SPDYStreamManager.h"
#import "SPDYTLSTrustEvaluator.h"

// The input buffer should be more than twice MAX_CHUNK_LENGTH and
// MAX_COMPRESSED_HEADER_BLOCK_LENGTH to avoid having to resize the
// buffer.
#define DEFAULT_WINDOW_SIZE            65536
#define INITIAL_INPUT_BUFFER_SIZE      65536
#define LOCAL_MAX_CONCURRENT_STREAMS   0
#define REMOTE_MAX_CONCURRENT_STREAMS  INT32_MAX
#define INCLUDE_SPDY_RESPONSE_HEADERS  1

@interface SPDYSession () <SPDYFrameDecoderDelegate, SPDYFrameEncoderDelegate, SPDYStreamDataDelegate, SPDYSocketDelegate>
@property (nonatomic, readonly) SPDYStreamId nextStreamId;
- (void)_sendSynStream:(SPDYStream *)stream streamId:(SPDYStreamId)streamId closeLocal:(bool)close;
- (void)_sendData:(SPDYStream *)stream;
- (void)_sendWindowUpdate:(uint32_t)deltaWindowSize streamId:(SPDYStreamId)streamId;
- (void)_sendPingResponse:(SPDYPingFrame *)pingFrame;
- (void)_sendRstStream:(SPDYStreamStatus)status streamId:(SPDYStreamId)streamId;
- (void)_sendGoAway:(SPDYSessionStatus)status;
@end

@implementation SPDYSession
{
    SPDYConfiguration *_configuration;
    SPDYFrameDecoder *_frameDecoder;
    SPDYFrameEncoder *_frameEncoder;
    SPDYStreamManager *_activeStreams;
    SPDYStreamManager *_inactiveStreams;
    SPDYSocket *_socket;
    NSMutableData *_inputBuffer;

    SPDYStreamId _lastGoodStreamId;
    SPDYStreamId _nextStreamId;
    CFAbsoluteTime _lastSocketActivity;
    CFAbsoluteTime _sessionPingOut;
    CFTimeInterval _sessionLatency;
    NSUInteger _bufferReadIndex;
    NSUInteger _bufferWriteIndex;
    uint32_t _initialSendWindowSize;
    uint32_t _initialReceiveWindowSize;
    uint32_t _sessionSendWindowSize;
    uint32_t _sessionReceiveWindowSize;
    uint32_t _localMaxConcurrentStreams;
    uint32_t _remoteMaxConcurrentStreams;
    bool _enableSettingsMinorVersion;
    bool _enableTCPNoDelay;
    bool _receivedGoAwayFrame;
    bool _sentGoAwayFrame;
    bool _cellular;
    bool _closing;
}

- (id)initWithOrigin:(SPDYOrigin *)origin
       configuration:(SPDYConfiguration *)configuration
            cellular:(bool)cellular
               error:(NSError **)pError
{
    NSParameterAssert(origin != nil);

    self = [super init];
    if (self) {
        if (!origin) {
            if (pError) {
                NSDictionary *info = @{ NSLocalizedDescriptionKey: @"cannot initialize SPDYSession without origin" };
                *pError = [[NSError alloc] initWithDomain:SPDYSessionErrorDomain
                                                     code:SPDYSessionInternalError
                                                 userInfo:info];
            }
            return nil;
        }

        SPDYSocket *socket = [[SPDYSocket alloc] initWithDelegate:self];
        bool connecting = [socket connectToHost:origin.host
                                         onPort:origin.port
                                    withTimeout:configuration.connectTimeout
                                          error:pError];

        if (connecting) {
            _configuration = configuration;
            _socket = socket;
            _origin = origin;
            SPDY_INFO(@"session connecting to %@", _origin);

            // TODO: for accuracy confirm this later from the socket
            _cellular = cellular;

            if ([_origin.scheme isEqualToString:@"https"]) {
                SPDY_DEBUG(@"session using TLS");
                [_socket secureWithTLS:configuration.tlsSettings];
            }

            _frameDecoder = [[SPDYFrameDecoder alloc] initWithDelegate:self];
            _frameEncoder = [[SPDYFrameEncoder alloc] initWithDelegate:self
                                                headerCompressionLevel:configuration.headerCompressionLevel];
            _activeStreams = [[SPDYStreamManager alloc] init];
            _inactiveStreams = [[SPDYStreamManager alloc] init];
            _inputBuffer = [[NSMutableData alloc] initWithCapacity:INITIAL_INPUT_BUFFER_SIZE];

            _lastGoodStreamId = 0;
            _nextStreamId = 1;
            _bufferReadIndex = 0;
            _bufferWriteIndex = 0;
            _sessionLatency = -1;

            _initialSendWindowSize = DEFAULT_WINDOW_SIZE;
            _initialReceiveWindowSize = (uint32_t)configuration.streamReceiveWindow;
            _localMaxConcurrentStreams = LOCAL_MAX_CONCURRENT_STREAMS;
            _remoteMaxConcurrentStreams = REMOTE_MAX_CONCURRENT_STREAMS;
            _enableSettingsMinorVersion = configuration.enableSettingsMinorVersion;
            _enableTCPNoDelay = configuration.enableTCPNoDelay;

            SPDYSettings *settings = [SPDYSettingsStore settingsForOrigin:_origin];
            if (settings != NULL) {
                if (settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].set) {
                    _remoteMaxConcurrentStreams = (uint32_t)MAX(settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].value, 0);
                }

                if (settings[SPDY_SETTINGS_INITIAL_WINDOW_SIZE].set) {
                    _initialSendWindowSize = (uint32_t)MAX(settings[SPDY_SETTINGS_INITIAL_WINDOW_SIZE].value, 0);
                }
            }

            _sessionSendWindowSize = DEFAULT_WINDOW_SIZE;
            _sessionReceiveWindowSize = (uint32_t)configuration.sessionReceiveWindow;
            _sentGoAwayFrame = NO;
            _receivedGoAwayFrame = NO;

            [_socket readDataWithTimeout:(NSTimeInterval)-1
                                  buffer:_inputBuffer
                            bufferOffset:_bufferWriteIndex
                                     tag:0];

            [self _sendServerPersistedSettings:settings];
            [self _sendClientSettings];

            uint32_t deltaWindowSize = _sessionReceiveWindowSize - DEFAULT_WINDOW_SIZE;
            [self _sendWindowUpdate:deltaWindowSize streamId:kSPDYSessionStreamId];
            if (_enableTCPNoDelay) {
                [self _sendPing:1];
            }
        } else {
            self = nil;
        }
    }
    return self;
}

- (void)issueRequest:(SPDYProtocol *)protocol
{
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:protocol dataDelegate:self];
    SPDY_INFO(@"%@: Issueing request %@ on Stream %@ with socket=%@", self, protocol, stream, _socket);

    if (_activeStreams.localCount >= _remoteMaxConcurrentStreams) {
        [_inactiveStreams addStream:stream];
        SPDY_INFO(@"max concurrent streams reached, deferring request");
        return;
    }

    [self _startStream:stream];
}

- (void)_issuePendingRequests
{
    SPDYStream *stream;

    while (_inactiveStreams.localCount > 0 && _activeStreams.localCount < _remoteMaxConcurrentStreams) {
        stream = [_inactiveStreams nextPriorityStream];
        [_inactiveStreams removeStreamForProtocol:stream.protocol];
        [self _startStream:stream];
    }
}

- (void)_startStream:(SPDYStream *)stream
{
    SPDYStreamId streamId = [self nextStreamId];
    [stream startWithStreamId:streamId
               sendWindowSize:_initialSendWindowSize
            receiveWindowSize:_initialReceiveWindowSize];
    _activeStreams[streamId] = stream;

    if (!stream.hasDataPending) {
        [self _sendSynStream:stream streamId:streamId closeLocal:YES];
        stream.localSideClosed = YES;
    } else {
        [self _sendSynStream:stream streamId:streamId closeLocal:NO];
        [self _sendData:stream];
    }
}

- (void)cancelRequest:(SPDYProtocol *)protocol
{
    SPDYStream *stream = _activeStreams[protocol];
    if (!stream) {
        stream = _inactiveStreams[protocol];
    }

    if (stream) {
        [self _sendRstStream:SPDY_STREAM_CANCEL streamId:stream.streamId];
        stream.client = nil;
        [_activeStreams removeStreamForProtocol:protocol];
        [_inactiveStreams removeStreamForProtocol:protocol];
        [self _issuePendingRequests];
    }
}

- (void)dealloc
{
    _socket.delegate = nil;
    _frameDecoder.delegate = nil;
    _frameEncoder.delegate = nil;
    [_socket disconnect];
}

- (bool)isCellular
{
    return _cellular;
}

- (bool)isOpen
{
    return (!_closing && !_receivedGoAwayFrame && !_sentGoAwayFrame);
}

- (void)close
{
    if (self.isOpen && _socket.runLoop) {
        _closing = YES;
        CFRunLoopPerformBlock([_socket.runLoop getCFRunLoop], kCFRunLoopDefaultMode, ^{
            [self _closeWithStatus:SPDY_SESSION_OK];
        });
    }
}

- (void)_closeWithStatus:(SPDYSessionStatus)status
{
    if (!_sentGoAwayFrame) {
        [self _sendGoAway:status];
    }
    for (SPDYStream *stream in _activeStreams) {
        [self _sendRstStream:SPDY_STREAM_CANCEL streamId:stream.streamId];
        [stream closeWithStatus:stream.local ? SPDY_STREAM_CANCEL : SPDY_STREAM_INTERNAL_ERROR];
    }

    [_activeStreams removeAllStreams];
    [_socket disconnectAfterWrites];
}

#pragma mark SPDYSocketDelegate

- (bool)socket:(SPDYSocket *)socket securedWithTrust:(SecTrustRef)trust
{
    _lastSocketActivity = CFAbsoluteTimeGetCurrent();
    id<SPDYTLSTrustEvaluator> evaluator = [SPDYProtocol sharedTLSTrustEvaluator];
    return evaluator == nil || [evaluator evaluateServerTrust:trust forHost:_origin.host];
}

- (void)socket:(SPDYSocket *)socket didConnectToHost:(NSString *)host port:(in_port_t)port
{
    _lastSocketActivity = CFAbsoluteTimeGetCurrent();
    SPDY_DEBUG(@"%@ socket connected to %@:%u", self, host, port);

    if(_enableTCPNoDelay){
        CFDataRef nativeSocket = CFWriteStreamCopyProperty(socket.cfWriteStream, kCFStreamPropertySocketNativeHandle);
        CFSocketNativeHandle *sock = (CFSocketNativeHandle *)CFDataGetBytePtr(nativeSocket);
        setsockopt(*sock, IPPROTO_TCP, TCP_NODELAY, &(int){ 1 }, sizeof(int));
        CFRelease(nativeSocket);
    }
}

- (void)socket:(SPDYSocket *)socket didReadData:(NSData *)data withTag:(long)tag
{
    _lastSocketActivity = CFAbsoluteTimeGetCurrent();
    SPDY_DEBUG(@"socket read[%li] (%lu)", tag, (unsigned long)data.length);

    _bufferWriteIndex += data.length;
    NSUInteger readableLength = _bufferWriteIndex - _bufferReadIndex;
    NSError *error = nil;

    // Decode as much as possible
    uint8_t *bytes = (uint8_t *)_inputBuffer.bytes + _bufferReadIndex;
    NSUInteger bytesRead = [_frameDecoder decode:bytes length:readableLength error:&error];

    // Close session on decoding errors
    if (error) {
        [self _closeWithStatus:SPDY_SESSION_PROTOCOL_ERROR];
        return;
    }

    _bufferReadIndex += bytesRead;

    // If we've successfully decoded all available input, reset the buffer
    if (_bufferReadIndex == _bufferWriteIndex) {
        _bufferReadIndex = 0;
        _bufferWriteIndex = 0;
    }

    SPDY_DEBUG(@"socket scheduling read[%li] (%lu:%lu)", (tag + 1), (unsigned long)_bufferReadIndex, (unsigned long)_bufferWriteIndex);
    [socket readDataWithTimeout:(NSTimeInterval)-1
                         buffer:_inputBuffer
                   bufferOffset:_bufferWriteIndex
                            tag:(tag + 1)];
}

- (void)socket:(SPDYSocket *)socket didWriteDataWithTag:(long)tag
{
    _lastSocketActivity = CFAbsoluteTimeGetCurrent();
    if (tag == 1) {
        _sessionPingOut = _lastSocketActivity;
    }
}

- (void)socket:(SPDYSocket *)socket didWritePartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
    _lastSocketActivity = CFAbsoluteTimeGetCurrent();
}

- (void)socket:(SPDYSocket *)socket willDisconnectWithError:(NSError *)error
{
    _lastSocketActivity = CFAbsoluteTimeGetCurrent();
    SPDY_WARNING(@"session connection error: %@", error);
    for (SPDYStream *stream in _activeStreams) {
        [stream closeWithError:error];
    }
    [_activeStreams removeAllStreams];
}

- (void)socketDidDisconnect:(SPDYSocket *)socket
{
    _lastSocketActivity = CFAbsoluteTimeGetCurrent();
    SPDY_INFO(@"%@: session connection closed", self);
    [[SPDYProtocol sessionManager] removeSession:self];
}

#pragma mark SPDYStreamDataDelegate

- (void)streamDataAvailable:(SPDYStream *)stream
{
    SPDY_DEBUG(@"request body stream data available");
    [self _sendData:stream];
}

- (void)streamFinished:(SPDYStream *)stream
{
    SPDY_DEBUG(@"request body stream finished");
    [self _sendData:stream];
}

#pragma mark SPDYFrameEncoderDelegate

- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder
{
    [_socket writeData:data withTimeout:(NSTimeInterval)-1 tag:0];
}

- (void)didEncodeData:(NSData *)data withTag:(uint32_t)tag frameEncoder:(SPDYFrameEncoder *)encoder
{
    [_socket writeData:data withTimeout:(NSTimeInterval)-1 tag:tag];
}

#pragma mark SPDYFrameDecoderDelegate

- (void)didReadDataFrame:(SPDYDataFrame *)dataFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    /*
     * SPDY Data frame processing requirements:
     *
     * If an endpoint receives a data frame for a Stream-ID which is not open
     * and the endpoint has not sent a GOAWAY frame, it must issue a stream error
     * with the error code INVALID_STREAM for the Stream-ID.
     *
     * If an endpoint which created the stream receives a data frame before receiving
     * a SYN_REPLY on that stream, it is a protocol error, and the recipient must
     * issue a stream error with the status code PROTOCOL_ERROR for the Stream-ID.
     *
     * If an endpoint receives multiple data frames for invalid Stream-IDs,
     * it may close the session.
     *
     * If an endpoint refuses a stream it must ignore any data frames for that stream.
     *
     * If an endpoint receives a data frame after the stream is half-closed from the
     * sender, it must send a RST_STREAM frame with the status STREAM_ALREADY_CLOSED.
     *
     * If an endpoint receives a data frame after the stream is closed, it must send
     * a RST_STREAM frame with the status PROTOCOL_ERROR.
     */

    SPDYStreamId streamId = dataFrame.streamId;
    SPDYStream *stream = _activeStreams[streamId];
    SPDY_DEBUG(@"received DATA.%u%@ (%lu)", streamId, dataFrame.last ? @"!" : @"", (unsigned long)dataFrame.data.length);

    // Check if session flow control is violated
    if (_sessionReceiveWindowSize < dataFrame.data.length) {
        [self _closeWithStatus:SPDY_SESSION_PROTOCOL_ERROR];
        return;
    }

    // Update session receive window size
    _sessionReceiveWindowSize -= dataFrame.data.length;

    // Send a WINDOW_UPDATE frame if less than half the session window size remains
    if (_sessionReceiveWindowSize <= _initialReceiveWindowSize / 2) {
        uint32_t deltaWindowSize = _initialReceiveWindowSize - _sessionReceiveWindowSize;
        [self _sendWindowUpdate:deltaWindowSize streamId:kSPDYSessionStreamId];
        _sessionReceiveWindowSize = _initialReceiveWindowSize;
    }

    // Check if we received a data frame for a valid Stream-ID
    if (!stream) {
        if (streamId < _lastGoodStreamId) {
            [self _sendRstStream:SPDY_STREAM_PROTOCOL_ERROR streamId:streamId];
        } else if (!_sentGoAwayFrame) {
            [self _sendRstStream:SPDY_STREAM_INVALID_STREAM streamId:streamId];
        }
        return;
    }

    // Check if we received a data frame for a stream which is half-closed
    if (stream.remoteSideClosed) {
        [self _sendRstStream:SPDY_STREAM_STREAM_ALREADY_CLOSED streamId:streamId];
        return;
    }

    // Check if we received a data frame before receiving a SYN_REPLY
    if (stream.local && !stream.receivedReply) {
        SPDY_WARNING(@"received data before SYN_REPLY");
        [self _sendRstStream:SPDY_STREAM_PROTOCOL_ERROR streamId:streamId];
        return;
    }

    /*
     * SPDY Data frame flow control processing requirements:
     *
     * Recipient should not send a WINDOW_UPDATE frame as it consumes the last data frame.
     */

    // Window size can become negative if we sent a SETTINGS frame that reduces the
    // size of the transfer window after the peer has written data frames.
    // The value is bounded by the length that SETTINGS frame decrease the window.
    // This difference is stored for the session when writing the SETTINGS frame
    // and is cleared once we send a WINDOW_UPDATE frame.
    // Note this can't currently happen in this implementation.
    if (stream.receiveWindowSize - dataFrame.data.length < stream.receiveWindowSizeLowerBound) {
        [self _sendRstStream:SPDY_STREAM_FLOW_CONTROL_ERROR streamId:streamId];
        return;
    }

    // Window size became negative due to sender writing frame before receiving SETTINGS
    // Send data frames upstream in initialReceiveWindowSize chunks
    if (dataFrame.data.length > _initialReceiveWindowSize) {
        NSUInteger dataOffset = 0;
        while (dataFrame.data.length - dataOffset > _initialReceiveWindowSize) {
            SPDYDataFrame *partialDataFrame = [[SPDYDataFrame alloc] init];
            partialDataFrame.streamId = streamId;
            partialDataFrame.last = NO;

            uint8_t *offsetBytes = ((uint8_t *)dataFrame.data.bytes + dataOffset);
            NSUInteger chunkLength = MIN(_initialReceiveWindowSize, dataFrame.data.length - dataOffset);
            partialDataFrame.data = [[NSData alloc] initWithBytesNoCopy:offsetBytes length:chunkLength freeWhenDone:NO];
            dataOffset += chunkLength;

            if (dataFrame.data.length - dataOffset <= _initialReceiveWindowSize) {
                partialDataFrame.last = dataFrame.last;
            }

            [self didReadDataFrame:partialDataFrame frameDecoder:frameDecoder];
        }
        return;
    }

    // Update receive window size
    stream.receiveWindowSize -= (uint32_t)dataFrame.data.length;

    // Send a WINDOW_UPDATE frame if less than half the window size remains
    if (stream.receiveWindowSize <= _initialReceiveWindowSize / 2 && !dataFrame.last) {
        // stream.receiveWindowSizeLowerBound = 0;
        [self _sendWindowUpdate:_initialReceiveWindowSize - stream.receiveWindowSize streamId:streamId];
        stream.receiveWindowSize = _initialReceiveWindowSize;
    }

    [stream didLoadData:dataFrame.data];

    stream.remoteSideClosed = dataFrame.last;
    if (stream.closed) {
        [_activeStreams removeStreamWithStreamId:streamId];
        [self _issuePendingRequests];
    }
}

- (void)didReadSynStreamFrame:(SPDYSynStreamFrame *)synStreamFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    /*
     * SPDY SYN_STREAM frame processing requirements:
     *
     * If an endpoint receives a SYN_STREAM with a Stream-ID that is less than
     * any previously received SYN_STREAM, it must issue a session error with
     * the status PROTOCOL_ERROR.
     *
     * If an endpoint receives multiple SYN_STREAM frames with the same active
     * Stream-ID, it must issue a stream error with the status code PROTOCOL_ERROR.
     *
     * The recipient can reject a stream by sending a stream error with the
     * status code REFUSED_STREAM.
     */

    SPDYStreamId streamId = synStreamFrame.streamId;
    SPDYStreamId associatedToStreamId = synStreamFrame.associatedToStreamId;
    SPDY_DEBUG(@"received SYN_STREAM.%u", streamId);
    
    // Stream-IDs must be monotonically increasing
    if (streamId <= _lastGoodStreamId) {
        [self _closeWithStatus:SPDY_SESSION_PROTOCOL_ERROR];
        return;
    }
    
    // || _activeStreams.remoteCount >= _localMaxConcurrentStreams) {
    if (_receivedGoAwayFrame) {
        [self _sendRstStream:SPDY_STREAM_REFUSED_STREAM streamId:streamId];
        return;
    }
    
    // If a client receives a server push stream with stream-id 0,
    // it MUST issue a session error (Section 2.4.1) with the status code PROTOCOL_ERROR.
    // Also the SYN_STREAM MUST include an Associated-To-Stream-ID,
    // and MUST set the FLAG_UNIDIRECTIONAL flag.
    if (streamId == 0 || associatedToStreamId == 0 || !synStreamFrame.unidirectional || !_activeStreams[associatedToStreamId]) {
        [self _closeWithStatus:SPDY_SESSION_PROTOCOL_ERROR];
        return;
    }
    
    // The SYN_STREAM MUST include headers for ":scheme", ":host",
    // ":path", which represent the URL for the resource being pushed.
    if (!synStreamFrame.headers[@":scheme"] ||
        !synStreamFrame.headers[@":host"] ||
        !synStreamFrame.headers[@":path"]) {
        [self _sendRstStream:SPDY_STREAM_REFUSED_STREAM streamId:streamId];
        return;
    }
    
    SPDYStream *stream = [[SPDYStream alloc] init];
    stream.priority = synStreamFrame.priority;
    stream.remoteSideClosed = synStreamFrame.last;
    stream.sendWindowSize = _initialSendWindowSize;
    stream.receiveWindowSize = _initialReceiveWindowSize;
    stream.local = NO;
    stream.streamId = streamId;
    stream.pushClient = self;
    stream.headers = synStreamFrame.headers;
    
    _lastGoodStreamId = streamId;
    _activeStreams[streamId] = stream;
}

- (void)didReadSynReplyFrame:(SPDYSynReplyFrame *)synReplyFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    /*
     * SPDY SYN_REPLY frame processing requirements:
     *
     * If an endpoint receives multiple SYN_REPLY frames for the same active Stream-ID
     * it must issue a stream error with the status code STREAM_IN_USE.
     */

    SPDYStreamId streamId = synReplyFrame.streamId;
    SPDYStream *stream = _activeStreams[streamId];
    SPDY_DEBUG(@"received SYN_REPLY.%u%@ (%@)", streamId, synReplyFrame.last ? @"!" : @"", synReplyFrame.headers[@":status"] ?: @"-");

    // Check if this is a reply for an active stream
    if (!stream) {
        [self _sendRstStream:SPDY_STREAM_INVALID_STREAM streamId:streamId];
        return;
    }

    // Check if we have received multiple frames for the same Stream-ID
    if (stream.receivedReply) {
        [self _sendRstStream:SPDY_STREAM_STREAM_IN_USE streamId:streamId];
        return;
    }

#if INCLUDE_SPDY_RESPONSE_HEADERS
    NSMutableDictionary *headers = [synReplyFrame.headers mutableCopy];
    headers[@"x-spdy-version"] = @"3.1";
    headers[@"x-spdy-parallelism"] = [[NSString alloc] initWithFormat:@"%lu", (unsigned long)_configuration.sessionPoolSize];
    headers[@"x-spdy-stream-id"] = [[NSString alloc] initWithFormat:@"%u", streamId];

    if (_sessionLatency > -1) {
        NSString *sessionLatencyMs = [@((int)(_sessionLatency * 1000)) stringValue];
        headers[@"x-spdy-session-latency"] = sessionLatencyMs;
    }
#else
    NSDictionary *headers = synReplyFrame.headers;
#endif

    [stream didReceiveResponse:headers];

    stream.remoteSideClosed = synReplyFrame.last;

    if (stream.closed) {
        [_activeStreams removeStreamWithStreamId:streamId];
        [self _issuePendingRequests];
    }
}

- (void)didReadRstStreamFrame:(SPDYRstStreamFrame *)rstStreamFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    /*
     * SPDY RST_STREAM frame processing requirements:
     *
     * After receiving a RST_STREAM on a stream, the receiver must not send
     * additional frames on that stream.
     *
     * An endpoint must not send a RST_STREAM in response to a RST_STREAM.
     */

    SPDYStreamId streamId = rstStreamFrame.streamId;
    SPDYStream *stream = _activeStreams[streamId];
    SPDY_DEBUG(@"received RST_STREAM.%u (%u)", streamId, rstStreamFrame.statusCode);

    if (stream) {
        [stream closeWithStatus:rstStreamFrame.statusCode];
        [_activeStreams removeStreamWithStreamId:streamId];
        [self _issuePendingRequests];
    }
}

- (void)didReadSettingsFrame:(SPDYSettingsFrame *)settingsFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    /*
     * SPDY SETTINGS frame processing requirements:
     *
     * When a client connects to a server, and the server persists settings
     * within the client, the client should return the persisted settings on
     * future connections to the same origin and IP address and TCP port (the
     * "origin" is the set of scheme, host, and port from the URI).
     */

    SPDY_DEBUG(@"received SETTINGS");

    SPDYSettings *settings = settingsFrame.settings;

    if (settingsFrame.clearSettings) {
        [SPDYSettingsStore clearSettingsForOrigin:nil];
    }

    bool persistSettings = NO;

    for (SPDYSettingsId i = _SPDY_SETTINGS_RANGE_START; !persistSettings && i < _SPDY_SETTINGS_RANGE_END; i++) {
        // Check if any settings need to be persisted before dispatching
        if (settings[i].set && settings[i].flags == SPDY_SETTINGS_FLAG_PERSIST_VALUE) {
            [SPDYSettingsStore persistSettings:settings forOrigin:_origin];
            persistSettings = YES;
        }
    }

    if (settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].set) {
        _remoteMaxConcurrentStreams = (uint32_t)MAX(settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].value, 0);
    }

    if (settings[SPDY_SETTINGS_INITIAL_WINDOW_SIZE].set) {
        uint32_t previousWindowSize = _initialSendWindowSize;
        _initialSendWindowSize = (uint32_t)MAX(settings[SPDY_SETTINGS_INITIAL_WINDOW_SIZE].value, 0);
        uint32_t deltaWindowSize = _initialSendWindowSize - previousWindowSize;

        for (SPDYStream *stream in _activeStreams) {
            if (!stream.localSideClosed) {
                stream.sendWindowSize = stream.sendWindowSize + deltaWindowSize;
                [self _sendData:stream];
            }
        }
    }

    [self _issuePendingRequests];
}

- (void)didReadPingFrame:(SPDYPingFrame *)pingFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    /*
     * SPDY PING frame processing requirements:
     *
     * Receivers of a PING frame should send an identical frame to the sender
     * as soon as possible.
     *
     * Receivers of a PING frame must ignore frames that it did not initiate
     */

    SPDYPingId pingId = pingFrame.pingId;

    if (pingId & 1) {
        if (pingId == 1) {
            _sessionLatency = CFAbsoluteTimeGetCurrent() - _sessionPingOut;
            SPDY_DEBUG(@"received PING.%u response (%f)", pingId, _sessionLatency);
        }
    } else {
        [self _sendPingResponse:pingFrame];
        SPDY_DEBUG(@"received PING.%u", pingId);
    }
}

- (void)didReadGoAwayFrame:(SPDYGoAwayFrame *)goAwayFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    SPDY_DEBUG(@"received GOAWAY.%u (%u)", goAwayFrame.lastGoodStreamId, goAwayFrame.statusCode);

    _receivedGoAwayFrame = YES;

    if (_activeStreams.count == 0) {
        [_socket disconnect];
    }
}

- (void)didReadHeadersFrame:(SPDYHeadersFrame *)headersFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    SPDYStreamId streamId = headersFrame.streamId;
    SPDYStream *stream = _activeStreams[streamId];
    SPDY_DEBUG(@"received HEADERS.%u", streamId);

    if (!stream || stream.remoteSideClosed) {
        [self _sendRstStream:SPDY_STREAM_INVALID_STREAM streamId:streamId];
        return;
    }

    stream.remoteSideClosed = headersFrame.last;
    if (stream.closed) {
        [_activeStreams removeStreamWithStreamId:streamId];
        [self _issuePendingRequests];
    }
}

- (void)didReadWindowUpdateFrame:(SPDYWindowUpdateFrame *)windowUpdateFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    /*
     * SPDY WINDOW_UPDATE frame processing requirements:
     *
     * Receivers of a WINDOW_UPDATE that cause the window size to exceed 2^31
     * must send a RST_STREAM with the status code FLOW_CONTROL_ERROR.
     *
     * Sender should ignore all WINDOW_UPDATE frames associated with a stream
     * after sending the last frame for the stream.
     */

    SPDYStreamId streamId = windowUpdateFrame.streamId;
    SPDY_DEBUG(@"received WINDOW_UPDATE.%u (+%lu)", streamId, (unsigned long)windowUpdateFrame.deltaWindowSize);

    if (streamId == kSPDYSessionStreamId) {
        // Check for numerical overflow
        if (_sessionSendWindowSize > INT32_MAX - windowUpdateFrame.deltaWindowSize) {
            [self _closeWithStatus:SPDY_SESSION_PROTOCOL_ERROR];
            return;
        }

        _sessionSendWindowSize += windowUpdateFrame.deltaWindowSize;
        for (SPDYStream *stream in _activeStreams) {
            [self _sendData:stream];
            if (_sessionSendWindowSize == 0) break;
        }

        return;
    }

    // Ignore frames for non-existent or half-closed streams
    SPDYStream *stream = _activeStreams[streamId];
    if (!stream || stream.localSideClosed) {
        return;
    }

    // Check for numerical overflow
    if (stream.sendWindowSize > INT32_MAX - windowUpdateFrame.deltaWindowSize) {
        [self _sendRstStream:SPDY_STREAM_FLOW_CONTROL_ERROR streamId:streamId];
        return;
    }

    stream.sendWindowSize += windowUpdateFrame.deltaWindowSize;
    [self _sendData:stream];
}

#pragma mark private methods

- (SPDYStreamId)nextStreamId
{
    SPDYStreamId streamId = _nextStreamId;
    _nextStreamId += 2;
    return streamId;
}

- (void)_sendServerPersistedSettings:(SPDYSettings *)persistedSettings
{
    if (persistedSettings != NULL) {
        SPDYSettingsFrame *settingsFrame = [[SPDYSettingsFrame alloc] init];
        SPDY_SETTINGS_ITERATOR(i) {
            settingsFrame.settings[i] = persistedSettings[i];
        }

        [_frameEncoder encodeSettingsFrame:settingsFrame];
        SPDY_DEBUG(@"sent server SETTINGS");
    }
}

- (void)_sendClientSettings
{
    SPDYSettingsFrame *settingsFrame = [[SPDYSettingsFrame alloc] init];
    if (_enableSettingsMinorVersion) {
        settingsFrame.settings[SPDY_SETTINGS_MINOR_VERSION].set = YES;
        settingsFrame.settings[SPDY_SETTINGS_MINOR_VERSION].flags = 0;
        settingsFrame.settings[SPDY_SETTINGS_MINOR_VERSION].value = 1;
    }
    settingsFrame.settings[SPDY_SETTINGS_INITIAL_WINDOW_SIZE].set = YES;
    settingsFrame.settings[SPDY_SETTINGS_INITIAL_WINDOW_SIZE].flags = 0;
    settingsFrame.settings[SPDY_SETTINGS_INITIAL_WINDOW_SIZE].value = (int32_t)_initialReceiveWindowSize;

    [_frameEncoder encodeSettingsFrame:settingsFrame];
    SPDY_DEBUG(@"sent client SETTINGS");
}

- (void)_sendSynStream:(SPDYStream *)stream streamId:(SPDYStreamId)streamId closeLocal:(bool)close
{
    SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = streamId;
    synStreamFrame.priority = stream.priority;
    synStreamFrame.unidirectional = NO;
    synStreamFrame.slot = 0;
    synStreamFrame.associatedToStreamId = 0;
    synStreamFrame.last = close;
    synStreamFrame.headers = stream.protocol.request.allSPDYHeaderFields;

    [_frameEncoder encodeSynStreamFrame:synStreamFrame];
    SPDY_DEBUG(@"sent SYN_STREAM.%u%@",streamId, synStreamFrame.last ? @"!" : @"");
}

- (void)_sendData:(SPDYStream *)stream
{
    SPDYStreamId streamId = stream.streamId;
    uint32_t sendWindowSize = MIN(_sessionSendWindowSize, stream.sendWindowSize);

    while (!stream.localSideClosed && stream.hasDataAvailable && sendWindowSize > 0) {
        NSError *error;
        NSData *data = [stream readData:sendWindowSize error:&error];

        if (data) {
            SPDYDataFrame *dataFrame = [[SPDYDataFrame alloc] init];
            dataFrame.streamId = streamId;
            dataFrame.data = data;
            dataFrame.last = !stream.hasDataPending;
            [_frameEncoder encodeDataFrame:dataFrame];
            SPDY_DEBUG(@"sent DATA.%u%@ (%lu)", streamId, dataFrame.last ? @"!" : @"", (unsigned long)dataFrame.data.length);

            uint32_t bytesSent = (uint32_t)data.length;
            sendWindowSize -= bytesSent;
            _sessionSendWindowSize -= bytesSent;
            stream.sendWindowSize -= bytesSent;
            stream.localSideClosed = dataFrame.last;
        } else {
            if (error) {
                [self _sendRstStream:SPDY_STREAM_CANCEL streamId:streamId];
                [stream closeWithError:error];
                [_activeStreams removeStreamWithStreamId:streamId];
                [self _issuePendingRequests];
            }

            // -[SPDYStream hasDataAvailable] may return true if we need to perform
            // a read on a stream to determine if data is actually available. This
            // mirrors Apple's API with [NSStream -hasBytesAvailable]. The break here
            // should technically be unnecessary, but it doesn't hurt.
            break;
        }
    }

    if (!stream.hasDataPending && !stream.localSideClosed) {
        SPDYDataFrame *dataFrame = [[SPDYDataFrame alloc] init];
        dataFrame.streamId = streamId;
        dataFrame.last = YES;
        [_frameEncoder encodeDataFrame:dataFrame];
        SPDY_DEBUG(@"sent DATA.%u%@ (%lu)", streamId, dataFrame.last ? @"!" : @"", (unsigned long)dataFrame.data.length);

        stream.localSideClosed = YES;
    }

    if (stream.closed) {
        [_activeStreams removeStreamWithStreamId:streamId];
        [self _issuePendingRequests];
    }
}

- (void)_sendWindowUpdate:(uint32_t)deltaWindowSize streamId:(SPDYStreamId)streamId
{
    SPDYWindowUpdateFrame *windowUpdateFrame = [[SPDYWindowUpdateFrame alloc] init];
    windowUpdateFrame.streamId = streamId;
    windowUpdateFrame.deltaWindowSize = deltaWindowSize;
    [_frameEncoder encodeWindowUpdateFrame:windowUpdateFrame];
    SPDY_DEBUG(@"sent WINDOW_UPDATE.%u (+%lu)", streamId, (unsigned long)deltaWindowSize);
}

- (void)_sendPing:(SPDYPingId)pingId
{
    SPDYPingFrame *pingFrame = [[SPDYPingFrame alloc] init];
    pingFrame.pingId = pingId;
    [_frameEncoder encodePingFrame:pingFrame];
    SPDY_DEBUG(@"sent PING.%u", pingId);
}

- (void)_sendPingResponse:(SPDYPingFrame *)pingFrame
{
    [_frameEncoder encodePingFrame:pingFrame];
    SPDY_DEBUG(@"sent PING.%u response", pingFrame.pingId);
}

- (void)_sendRstStream:(SPDYStreamStatus)status streamId:(SPDYStreamId)streamId
{
    SPDYRstStreamFrame *rstStreamFrame = [[SPDYRstStreamFrame alloc] init];
    rstStreamFrame.streamId = streamId;
    rstStreamFrame.statusCode = status;
    [_frameEncoder encodeRstStreamFrame:rstStreamFrame];
    SPDY_DEBUG(@"sent RST_STREAM.%u", streamId);
}

- (void)_sendGoAway:(SPDYSessionStatus)status
{
    SPDYGoAwayFrame *goAwayFrame = [[SPDYGoAwayFrame alloc] init];
    goAwayFrame.lastGoodStreamId = _lastGoodStreamId;
    goAwayFrame.statusCode = status;
    [_frameEncoder encodeGoAwayFrame:goAwayFrame];
    SPDY_DEBUG(@"sent GO_AWAY");
    _sentGoAwayFrame = YES;
}

#pragma mark SPDYStreamPushClient

- (void)stream:(SPDYStream *)stream didReceivePushResponse:(NSURLResponse *)response data:(NSData *)data
{
    if ([[self delegate] respondsToSelector:@selector(session:didReceivePushResponse:data:)]) {
        [[self delegate] session:self didReceivePushResponse:response data:data];
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@:%p isOpen=%@>", [self class], self, self.isOpen ? @"YES" : @"NO"];
}

@end
