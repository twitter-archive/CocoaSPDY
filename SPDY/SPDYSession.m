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
#import "SPDYSession.h"
#import "SPDYCommonLogger.h"
#import "SPDYFrameDecoder.h"
#import "SPDYFrameEncoder.h"
#import "SPDYMetadata+Utils.h"
#import "SPDYOrigin.h"
#import "SPDYOriginEndpoint.h"
#import "SPDYProtocol+Project.h"
#import "SPDYSettingsStore.h"
#import "SPDYSocket.h"
#import "SPDYStopwatch.h"
#import "SPDYStream.h"
#import "SPDYStreamManager.h"

// The input buffer should be more than twice MAX_CHUNK_LENGTH and
// MAX_COMPRESSED_HEADER_BLOCK_LENGTH to avoid having to resize the
// buffer.
#define DEFAULT_WINDOW_SIZE            65536
#define INITIAL_INPUT_BUFFER_SIZE      65536
#define LOCAL_MAX_CONCURRENT_STREAMS   32
#define REMOTE_MAX_CONCURRENT_STREAMS  INT32_MAX

@interface SPDYSession () <SPDYFrameDecoderDelegate, SPDYFrameEncoderDelegate, SPDYStreamDelegate, SPDYSocketDelegate>
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
    SPDYSocket *_socket;
    NSError *_socketError;
    NSMutableData *_inputBuffer;

    SPDYStreamId _lastGoodStreamId;
    SPDYStopwatch *_sessionPingStopwatch;
    SPDYTimeInterval _sessionLatency;
    NSUInteger _bufferReadIndex;
    NSUInteger _bufferWriteIndex;
    uint32_t _initialSendWindowSize;
    uint32_t _initialReceiveWindowSize;
    uint32_t _sessionSendWindowSize;
    uint32_t _sessionReceiveWindowSize;
    uint32_t _localMaxConcurrentStreams;
    uint32_t _remoteMaxConcurrentStreams;
    bool _cellular;
    bool _connected;
    bool _disconnected;
    bool _enableSettingsMinorVersion;
    bool _enableTCPNoDelay;
    bool _established;
    bool _receivedGoAwayFrame;
    bool _sentGoAwayFrame;
    SPDYStopwatch *_connectedStopwatch;
}

- (instancetype)initWithOrigin:(SPDYOrigin *)origin
            delegate:(id<SPDYSessionDelegate>)delegate
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

        _sessionPingStopwatch = [[SPDYStopwatch alloc] init];
        _connectedStopwatch = [[SPDYStopwatch alloc] init];

        SPDYSocket *socket = [[SPDYSocket alloc] initWithDelegate:self];
        bool connecting = [socket connectToOrigin:origin
                                      withTimeout:configuration.connectTimeout
                                            error:pError];

        if (connecting) {
            _delegate = delegate;
            _configuration = configuration;
            _socket = socket;
            _origin = origin;
            SPDY_INFO(@"%@ connecting to %@", self, _origin);

            _cellular = cellular;

            if ([_origin.scheme isEqualToString:@"https"]) {
                SPDY_DEBUG(@"%@ using TLS", self);
                [_socket secureWithTLS:configuration.tlsSettings];
            }

            _frameDecoder = [[SPDYFrameDecoder alloc] initWithDelegate:self];
            _frameEncoder = [[SPDYFrameEncoder alloc] initWithDelegate:self
                                                headerCompressionLevel:configuration.headerCompressionLevel];
            _activeStreams = [[SPDYStreamManager alloc] init];
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

            _connected = NO;
            _disconnected = NO;
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

- (void)openStream:(SPDYStream *)stream
{
//    NSAssert(_connected, @"Cannot open stream prior to connecting.");

    SPDYStreamId streamId = _nextStreamId;
    _nextStreamId += 2;
    stream.delegate = self;

    if (_sessionLatency >= 0) {
        stream.metadata.latencyMs = (NSInteger)(_sessionLatency * 1000);
    }
    stream.metadata.timeSessionConnected = _connectedStopwatch.startSystemTime;
    stream.metadata.connectedMs = _connectedStopwatch.elapsedSeconds * 1000;
    stream.metadata.hostAddress = _socket.connectedHost;
    stream.metadata.hostPort = _socket.connectedPort;
    stream.metadata.viaProxy = _socket.connectedToProxy;
    stream.metadata.proxyStatus = _socket.proxyStatus;
    stream.metadata.cellular = _cellular;
    stream.metadata.loadSource = SPDYLoadSourceNetwork;

    [stream startWithStreamId:streamId
               sendWindowSize:_initialSendWindowSize
            receiveWindowSize:_initialReceiveWindowSize];
    _activeStreams[streamId] = stream;

    stream.metadata.timeStreamRequestStarted = [SPDYStopwatch currentSystemTime];

    if (!stream.hasDataPending) {
        [self _sendSynStream:stream streamId:streamId closeLocal:YES];
        stream.localSideClosed = YES;
    } else {
        [self _sendSynStream:stream streamId:streamId closeLocal:NO];
        [self _sendData:stream];
    }
}

- (NSUInteger)capacity
{
    return (self.isOpen && _connected) * MAX(0, _remoteMaxConcurrentStreams - _activeStreams.localCount);
}

- (NSUInteger)load
{
    return _activeStreams.localCount;
}

- (void)dealloc
{
    _frameDecoder.delegate = nil;
    _frameEncoder.delegate = nil;
}

- (bool)isCellular
{
    return _cellular;
}

- (bool)isConnected
{
    return _connected;
}

- (bool)isEstablished
{
    return _established;
}

- (bool)isOpen
{
    return (!_receivedGoAwayFrame && !_sentGoAwayFrame && !_disconnected);
}

- (void)close
{
    [self _closeWithStatus:SPDY_SESSION_OK];
}

- (void)_closeWithStatus:(SPDYSessionStatus)status
{
    if (!_sentGoAwayFrame) {
        [self _sendGoAway:status];
    }

    SPDYStreamStatus streamStatus;
    switch (status) {
        case SPDY_SESSION_OK:
            streamStatus = SPDY_STREAM_CANCEL;
            break;
        case SPDY_SESSION_PROTOCOL_ERROR:
            streamStatus = SPDY_STREAM_PROTOCOL_ERROR;
            break;
        default:
            streamStatus = SPDY_STREAM_INTERNAL_ERROR;
    }

    for (SPDYStream *stream in _activeStreams) {
        [self _sendRstStream:streamStatus streamId:stream.streamId];
        stream.delegate = nil;
        [stream closeWithError:SPDY_STREAM_ERROR((SPDYStreamError)streamStatus, @"SPDY stream closed.")];
    }

    [_activeStreams removeAllStreams];
    [_socket disconnectAfterWrites];
}

#pragma mark SPDYSocketDelegate

- (bool)socket:(SPDYSocket *)socket securedWithTrust:(SecTrustRef)trust
{
    return [SPDYProtocol evaluateServerTrust:trust forHost:_origin.host];
}

- (void)socket:(SPDYSocket *)socket didConnectToHost:(NSString *)host port:(in_port_t)port
{
    [_connectedStopwatch reset];
    SPDY_INFO(@"%@ connected to %@ (%@:%u)", self, _origin, host, port);

    if (_cellular != socket.isCellular) {
        SPDY_WARNING(@"%@ expected network type %@ but socket is %@",
                self, _cellular ? @"cellular" : @"wifi",
                socket.isCellular ? @"cellular" : @"wifi");

        _cellular = socket.isCellular;

        // Update metadata
        for (SPDYStream *stream in _activeStreams) {
            stream.metadata.cellular = _cellular;
        }
    }

    _connected = YES;
    [_delegate session:self connectedToNetwork:_cellular];

    if(_enableTCPNoDelay){
        CFDataRef nativeSocket = CFWriteStreamCopyProperty(socket.cfWriteStream, kCFStreamPropertySocketNativeHandle);
        CFSocketNativeHandle *sock = (CFSocketNativeHandle *)CFDataGetBytePtr(nativeSocket);
        setsockopt(*sock, IPPROTO_TCP, TCP_NODELAY, &(int){ 1 }, sizeof(int));
        CFRelease(nativeSocket);
    }
}

- (void)socket:(SPDYSocket *)socket didReadData:(NSData *)data withTag:(long)tag
{
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
    if (tag == 1) {
        [_sessionPingStopwatch reset];
    }
}

//- (void)socket:(SPDYSocket *)socket didWriteDataForStreamId:(SPDYStreamId)streamId
//{
//
//}
//
//- (void)socket:(SPDYSocket *)socket didWritePingForPingId:(SPDYPingId)pingId
//{
//
//}

- (void)socket:(SPDYSocket *)socket didWritePartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
}

- (void)socket:(SPDYSocket *)socket willDisconnectWithError:(NSError *)error
{
    SPDY_INFO(@"%@ connection error: %@", self, error);
    _socketError = error;
    for (SPDYStream *stream in _activeStreams) {
        stream.delegate = nil;
        [stream closeWithError:error];
    }
    [_activeStreams removeAllStreams];
}

- (void)socketDidDisconnect:(SPDYSocket *)socket
{
    SPDY_INFO(@"%@ connection closed", self);

    _connected = NO;
    _disconnected = YES;
    _socket = nil;

    [_delegate sessionClosed:self error:_socketError];
    _delegate = nil;
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
    SPDY_DEBUG(@"received %@DATA.%u%@ (frame %tu, data %tu)", (dataFrame.headerLength == 0) ? @"synthesized " : @"", streamId, dataFrame.last ? @"!" : @"", dataFrame.encodedLength, dataFrame.data.length);

    // Perform receive bytes accounting here. Beware the recursive call back into this function
    // below for partial data frame chunking. Don't double-add.
    if (stream) {
        // A data frame can get broken up into multiple TCP segments, which results in multiple
        // synthesized data frames being passed into this callback.
        stream.metadata.rxBytes += dataFrame.data.length + dataFrame.headerLength;
        stream.metadata.rxBodyBytes += dataFrame.data.length + dataFrame.headerLength;
        if (stream.metadata.timeStreamResponseFirstData == 0) {
            stream.metadata.timeStreamResponseFirstData = [SPDYStopwatch currentSystemTime];
        }
        stream.metadata.timeStreamResponseLastData = [SPDYStopwatch currentSystemTime];
    }

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
        [stream abortWithError:SPDY_STREAM_ERROR(SPDYStreamProtocolError, @"received data before syn reply") status:SPDY_STREAM_PROTOCOL_ERROR];
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
    // TODO: all of these variables are unsigned, how can this statement ever work?
    if (stream.receiveWindowSize - dataFrame.data.length < stream.receiveWindowSizeLowerBound) {
        [stream abortWithError:SPDY_STREAM_ERROR(SPDYStreamProtocolError, @"flow control window error") status:SPDY_STREAM_FLOW_CONTROL_ERROR];
        return;
    }

    // Window size became negative due to sender writing frame before receiving SETTINGS
    // Send data frames upstream in initialReceiveWindowSize chunks
    if (dataFrame.data.length > _initialReceiveWindowSize) {

        NSUInteger dataOffset = 0;
        while (dataFrame.data.length - dataOffset > _initialReceiveWindowSize) {
            // These chunked frames were never actually transmitted, so their encoded length is 0
            SPDYDataFrame *partialDataFrame = [[SPDYDataFrame alloc] initWithLength:0];
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

    if (!stream.closed) {
        stream.remoteSideClosed = dataFrame.last;
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
    SPDYStream *associatedStream = _activeStreams[associatedToStreamId];
    SPDY_DEBUG(@"received SYN_STREAM.%u associated %u", streamId, associatedToStreamId);

    // Stream-IDs must be monotonically increasing
    if (streamId <= _lastGoodStreamId) {
        [self _closeWithStatus:SPDY_SESSION_PROTOCOL_ERROR];
        return;
    }

    // Session must be active and still have room for incoming streams
    if (_receivedGoAwayFrame || _activeStreams.remoteCount >= _localMaxConcurrentStreams) {
        [self _sendRstStream:SPDY_STREAM_REFUSED_STREAM streamId:streamId];
        return;
    }

    // If a client receives a server push stream with stream-id 0,
    // it MUST issue a session error (Section 2.4.1) with the status code PROTOCOL_ERROR.
    // Also the SYN_STREAM MUST include an Associated-To-Stream-ID,
    // and MUST set the FLAG_UNIDIRECTIONAL flag.
    // TODO: confirm shutting down the connection is the right thing to do for all these cases.
    // If no associated stream, send GOAWAY or just refuse stream?
    if (streamId == 0 || associatedToStreamId == 0 || !synStreamFrame.unidirectional || !associatedStream) {
        [self _closeWithStatus:SPDY_SESSION_PROTOCOL_ERROR];
        return;
    }

    SPDYStream *stream = [[SPDYStream alloc] initWithAssociatedStream:associatedStream
                                                             priority:synStreamFrame.priority];

    stream.metadata.rxBytes += synStreamFrame.encodedLength;

    SPDYTimeInterval now = [SPDYStopwatch currentSystemTime];
    stream.metadata.timeStreamRequestStarted = now;
    stream.metadata.timeStreamRequestLastHeader = now;
    stream.metadata.timeStreamResponseStarted = now;

    [stream startWithStreamId:streamId
               sendWindowSize:_initialSendWindowSize
            receiveWindowSize:_initialReceiveWindowSize];

    _lastGoodStreamId = streamId;
    _activeStreams[streamId] = stream;

    [stream mergeHeaders:synStreamFrame.headers];
    [stream didReceivePushRequest];

    if (!stream.closed) {
        stream.remoteSideClosed = synStreamFrame.last;
    }
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

    stream.metadata.rxBytes += synReplyFrame.encodedLength;
    stream.metadata.timeStreamResponseStarted = [SPDYStopwatch currentSystemTime];
    stream.metadata.timeStreamResponseLastHeader = [SPDYStopwatch currentSystemTime];

    // While we prefer to record latencyMs at stream open time, the ping response may not have been
    // received yet. It will have been received by this point however.
    if (_sessionLatency >= 0 && stream.metadata.latencyMs <= 0) {
        stream.metadata.latencyMs = (NSInteger)(_sessionLatency * 1000);
    }

    // Check if we have received multiple frames for the same Stream-ID
    if (stream.receivedReply) {
        SPDY_WARNING(@"received duplicate SYN_REPLY");
        [stream abortWithError:SPDY_STREAM_ERROR(SPDYStreamStreamInUse, @"duplicate syn reply stream id") status:SPDY_STREAM_STREAM_IN_USE];
        return;
    }

    [stream mergeHeaders:synReplyFrame.headers];
    [stream didReceiveResponse];

    if (!stream.closed) {
        stream.remoteSideClosed = synReplyFrame.last;
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
        if (rstStreamFrame.statusCode == SPDY_STREAM_REFUSED_STREAM && [stream reset]) {
            [_delegate session:self refusedStream:stream];
            return;
        }

        stream.metadata.rxBytes += rstStreamFrame.encodedLength;
        [stream closeWithError:SPDY_STREAM_ERROR((SPDYStreamError)rstStreamFrame.statusCode, @"SPDY stream closed.")];
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
    bool capacityIncreased = NO;
    NSUInteger maxConcurrentStreamsDelta = 0;

    for (SPDYSettingsId i = _SPDY_SETTINGS_RANGE_START; !persistSettings && i < _SPDY_SETTINGS_RANGE_END; i++) {
        // Check if any settings need to be persisted before dispatching
        if (settings[i].set && settings[i].flags == SPDY_SETTINGS_FLAG_PERSIST_VALUE) {
            [SPDYSettingsStore persistSettings:settings forOrigin:_origin];
            persistSettings = YES;
        }
    }

    if (settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].set) {
        uint32_t newMaxConcurrentStreams = (uint32_t)MAX(settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].value, 0);
        maxConcurrentStreamsDelta = newMaxConcurrentStreams - _remoteMaxConcurrentStreams;
        capacityIncreased = newMaxConcurrentStreams > _remoteMaxConcurrentStreams;
        _remoteMaxConcurrentStreams = newMaxConcurrentStreams;
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

    if (capacityIncreased) {
        [_delegate session:self capacityIncreased:maxConcurrentStreamsDelta];
    }
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
            _sessionLatency = _sessionPingStopwatch.elapsedSeconds;
            SPDY_DEBUG(@"received PING.%u response (%f)", pingId, _sessionLatency);
            _established = YES;
        }
    } else {
        SPDY_DEBUG(@"received PING.%u", pingId);
        [self _sendPingResponse:pingFrame];
    }
}

- (void)didReadGoAwayFrame:(SPDYGoAwayFrame *)goAwayFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    SPDY_DEBUG(@"received GOAWAY.%u (%u)", goAwayFrame.lastGoodStreamId, goAwayFrame.statusCode);

    _receivedGoAwayFrame = YES;

    NSMutableArray *unhandledStreams = [[NSMutableArray alloc] initWithCapacity:_activeStreams.localCount];
    for (SPDYStream *stream in _activeStreams) {
        SPDYStreamId streamId = stream.streamId;
        if (stream.local && streamId > goAwayFrame.lastGoodStreamId) {
            [unhandledStreams addObject:stream];
            stream.delegate = nil;

            // Note: be careful of how reset mutates a stream. We need to be able to remove
            // the stream from _activeStreams down below.
            if ([stream reset]) {
                [_delegate session:self refusedStream:stream];
            } else {
                [stream closeWithError:SPDY_SESSION_ERROR(goAwayFrame.statusCode, @"SPDY session closed")];
            }
        }
    }

    for (SPDYStream *stream in unhandledStreams) {
        NSAssert(stream.protocol, @"expect protocol to be non-nil");
        [_activeStreams removeStreamForProtocol:stream.protocol];
    }

    [_delegate sessionClosed:self error:nil];
    _delegate = nil;

    if (_activeStreams.count == 0) {
        [self close];
    }
}

- (void)didReadHeadersFrame:(SPDYHeadersFrame *)headersFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder
{
    SPDYStreamId streamId = headersFrame.streamId;
    SPDYStream *stream = _activeStreams[streamId];
    SPDY_DEBUG(@"received HEADERS.%u", streamId);

    if (stream) {
        stream.metadata.rxBytes += headersFrame.encodedLength;
    }

    if (!stream || stream.remoteSideClosed) {
        [self _sendRstStream:SPDY_STREAM_INVALID_STREAM streamId:streamId];
        return;
    }

    // If the server sends a HEADER frame containing duplicate headers
    // with a previous HEADERS frame for the same stream, the client must
    // issue a stream error (Section 2.4.2) with error code PROTOCOL ERROR.
    [stream mergeHeaders:headersFrame.headers];

    if (!stream.closed) {
        // This is the "response" for a push request
        if (!stream.local) {
            stream.metadata.timeStreamResponseLastHeader = [SPDYStopwatch currentSystemTime];
            [stream didReceiveResponse];
        }
        stream.remoteSideClosed = headersFrame.last;
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
        stream.remoteSideClosed = YES;
        return;
    }

    stream.sendWindowSize += windowUpdateFrame.deltaWindowSize;
    [self _sendData:stream];
}

#pragma mark SPDYStreamDelegate

- (void)streamCanceled:(SPDYStream *)stream status:(SPDYStreamStatus)status
{
    SPDY_INFO(@"stream %u canceled, status %u", stream.streamId, status);
    NSAssert(_activeStreams[stream.streamId], @"stream delegate must be managing stream");

    [self _sendRstStream:status streamId:stream.streamId];
}

- (void)streamClosed:(SPDYStream *)stream
{
    stream.delegate = nil;

    SPDYTimeInterval now = [SPDYStopwatch currentSystemTime];
    if (stream.metadata.timeStreamRequestStarted > 0 && stream.metadata.timeStreamRequestEnded == 0) {
        stream.metadata.timeStreamRequestEnded = now;
    }
    if (stream.metadata.timeStreamResponseStarted > 0 && stream.metadata.timeStreamResponseEnded == 0) {
        stream.metadata.timeStreamResponseEnded = now;
    }
    stream.metadata.timeStreamClosed = now;

    [_activeStreams removeStreamWithStreamId:stream.streamId];
    if (!_receivedGoAwayFrame) {
        [_delegate session:self capacityIncreased:1];
    } else if (_activeStreams.count == 0) {
        [self close];
    }
}

- (void)streamDataAvailable:(SPDYStream *)stream
{
    SPDY_DEBUG(@"request body stream data available");
    [self _sendData:stream];
}

- (void)streamDataFinished:(SPDYStream *)stream
{
    SPDY_DEBUG(@"request body stream finished");
    [self _sendData:stream];
}

#pragma mark private methods

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

    NSError *error;
    NSInteger result = [_frameEncoder encodeSynStreamFrame:synStreamFrame error:&error];
    stream.metadata.timeStreamRequestLastHeader = [SPDYStopwatch currentSystemTime];
    if (result <= 0) {
        SPDY_ERROR(@"error encoding SYN_STREAM.%u%@",streamId, synStreamFrame.last ? @"!" : @"");
        [stream closeWithError:error];
    } else {
        stream.metadata.txBytes += result;
        SPDY_DEBUG(@"sent SYN_STREAM.%u%@",streamId, synStreamFrame.last ? @"!" : @"");
    }
}

- (void)_sendData:(SPDYStream *)stream
{
    SPDYStreamId streamId = stream.streamId;
    uint32_t sendWindowSize = MIN(_sessionSendWindowSize, stream.sendWindowSize);

    // Only track flow control blocks
    if (stream.localSideClosed || !stream.hasDataAvailable || sendWindowSize > 0) {
        [stream markUnblocked];
    } else {
        [stream markBlocked];
    }

    while (!stream.localSideClosed && stream.hasDataAvailable && sendWindowSize > 0) {
        NSError *error;
        NSData *data = [stream readData:sendWindowSize error:&error];

        if (data) {
            SPDYDataFrame *dataFrame = [[SPDYDataFrame alloc] init];
            dataFrame.streamId = streamId;
            dataFrame.data = data;
            dataFrame.last = !stream.hasDataPending;
            NSInteger result = [_frameEncoder encodeDataFrame:dataFrame];
            SPDY_DEBUG(@"sent DATA.%u%@ (%lu)", streamId, dataFrame.last ? @"!" : @"", (unsigned long)dataFrame.data.length);

            if (stream.metadata.timeStreamRequestFirstData == 0) {
                stream.metadata.timeStreamRequestFirstData = [SPDYStopwatch currentSystemTime];
            }
            stream.metadata.timeStreamRequestLastData = [SPDYStopwatch currentSystemTime]; // keeps updating as we go

            // On-the-wire byte accounting
            if (result > 0) {
                stream.metadata.txBytes += result;
                stream.metadata.txBodyBytes += result;
            }

            // SPDY window accounting
            uint32_t bytesSent = (uint32_t)data.length;
            sendWindowSize -= bytesSent;
            _sessionSendWindowSize -= bytesSent;
            stream.sendWindowSize -= bytesSent;
            stream.localSideClosed = dataFrame.last;
        } else {
            if (error) {
                [stream abortWithError:error status:SPDY_STREAM_INTERNAL_ERROR];
                return;
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
        NSInteger result = [_frameEncoder encodeDataFrame:dataFrame];
        SPDY_DEBUG(@"sent DATA.%u%@ (%lu)", streamId, dataFrame.last ? @"!" : @"", (unsigned long)dataFrame.data.length);

        if (stream.metadata.timeStreamRequestFirstData == 0) {
            stream.metadata.timeStreamRequestFirstData = [SPDYStopwatch currentSystemTime];
        }
        stream.metadata.timeStreamRequestLastData = [SPDYStopwatch currentSystemTime]; // keeps updating as we go

        if (result > 0) {
            stream.metadata.txBytes += result;
            stream.metadata.txBodyBytes += result;
        }
        stream.localSideClosed = YES;
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
    SPDY_DEBUG(@"sent RST_STREAM.%u (%u)", streamId, status);
}

- (void)_sendGoAway:(SPDYSessionStatus)status
{
    SPDYGoAwayFrame *goAwayFrame = [[SPDYGoAwayFrame alloc] init];
    goAwayFrame.lastGoodStreamId = _lastGoodStreamId;
    goAwayFrame.statusCode = status;
    [_frameEncoder encodeGoAwayFrame:goAwayFrame];
    SPDY_DEBUG(@"sent GO_AWAY (%u)", status);
    _sentGoAwayFrame = YES;
}

@end
