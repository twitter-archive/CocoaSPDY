//
//  SPDYFrameDecoder.m
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

#import "SPDYFrameDecoder.h"
#import "SPDYHeaderBlockDecompressor.h"

#define SPDY_VERSION 3
#define SPDY_COMMON_HEADER_SIZE 8
#define MAX_HEADER_BLOCK_LENGTH 32768

typedef struct {
    bool ctrl;
    union {
        struct {
            uint16_t version;
            uint16_t type;
        } control;
        struct {
            uint32_t streamId;
        } data;
    };
    uint8_t flags;
    uint32_t length;
} SPDYCommonHeader;

typedef enum {
    READ_COMMON_HEADER,
    READ_CONTROL_FRAME,
    READ_SETTINGS,
    READ_HEADER_BLOCK,
    READ_DATA_FRAME,
    FRAME_ERROR
} SPDYFrameDecoderState;

@interface SPDYFrameDecoder ()
- (NSUInteger)_readCommonHeader:(uint8_t *)buffer length:(NSUInteger)len;
- (NSUInteger)_readControlFrame:(uint8_t *)buffer length:(NSUInteger)len;
- (NSUInteger)_readDataFrame:(uint8_t *)buffer length:(NSUInteger)len;
- (NSUInteger)_readHeaderBlock:(uint8_t *)buffer length:(NSUInteger)len;
- (NSUInteger)_readSettings:(uint8_t *)buffer length:(NSUInteger)len;
@end

@implementation SPDYFrameDecoder
{
    SPDYHeaderBlockDecompressor *_decompressor;
    SPDYHeaderBlockFrame *_headerBlockFrame;
    SPDYSettingsFrame *_settingsFrame;
    SPDYCommonHeader _header;
    SPDYControlFrameType _type;
    SPDYFrameDecoderState _state;
    NSUInteger _decompressedLength;
    NSUInteger _length;
    NSUInteger _maxHeaderBlockLength;
    uint8_t *_decompressed;
}

int32_t getSignedInt32(uint8_t *buffer) {
    return ntohl(*(int32_t *)buffer);
}

uint32_t getUnsignedInt32(uint8_t *buffer) {
    return ntohl(*(uint32_t *)buffer);
}

uint32_t getUnsignedInt31(uint8_t *buffer) {
    return getUnsignedInt32(buffer) & 0x7FFFFFFF;
}

uint32_t getUnsignedInt24(uint8_t *buffer) {
    return getUnsignedInt32(buffer) & 0x00FFFFFF;
}

uint16_t getUnsignedInt16(uint8_t *buffer) {
    return ntohs(*(uint16_t *)buffer);
}

uint16_t getUnsignedInt15(uint8_t *buffer) {
    return getUnsignedInt16(buffer) & (uint16_t)0x7FFF;
}

SPDYCommonHeader getCommonHeader(uint8_t *buffer) {
    SPDYCommonHeader header;
    header.ctrl = (buffer[0] & 0x80) != 0;
    if (header.ctrl) {
        header.control.version = getUnsignedInt15(buffer);
        header.control.type = getUnsignedInt16(buffer + 2);
    } else {
        header.data.streamId = getUnsignedInt32(buffer);
    }
    header.flags = buffer[4];
    header.length = getUnsignedInt24(buffer + 4);
    return header;
}


- (id)initWithDelegate:(id)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _maxHeaderBlockLength = MAX_HEADER_BLOCK_LENGTH;
        _state = READ_COMMON_HEADER;

        _decompressor = [[SPDYHeaderBlockDecompressor alloc] init];
        _decompressed = malloc(sizeof(uint8_t) * MAX_HEADER_BLOCK_LENGTH);
        _decompressedLength = 0;
    }
    return self;
}

- (void)dealloc
{
    free(_decompressed);
}

- (NSUInteger)decode:(uint8_t *)buffer length:(NSUInteger)len error:(NSError **)pError;
{
    NSUInteger bytesRead = 0;
    NSUInteger totalBytesRead = 0;

    SPDYFrameDecoderState previousState;
    do {
        previousState = _state;

        switch (_state) {
            case READ_COMMON_HEADER:
                bytesRead = [self _readCommonHeader:buffer length:len];
                break;
            case READ_CONTROL_FRAME:
                bytesRead = [self _readControlFrame:buffer length:len];
                break;
            case READ_SETTINGS:
                bytesRead = [self _readSettings:buffer length:len];
                break;
            case READ_HEADER_BLOCK:
                bytesRead = [self _readHeaderBlock:buffer length:len];
                break;
            case READ_DATA_FRAME:
                bytesRead = [self _readDataFrame:buffer length:len];
                break;
            case FRAME_ERROR:
                bytesRead = 0;
                if (pError) {
                    *pError = [[NSError alloc] initWithDomain:@"com.twitter.spdy.decoder"
                                                        code:SPDY_SESSION_PROTOCOL_ERROR
                                                    userInfo:nil];
                }
                break;
        }

        totalBytesRead += bytesRead;
        buffer += bytesRead;
        len -= bytesRead;
    } while (previousState != _state);

    return totalBytesRead;
}

#pragma mark private methods

- (NSUInteger)_readCommonHeader:(uint8_t *)buffer length:(NSUInteger)len
{
    if (SPDY_COMMON_HEADER_SIZE <= len) {
        _header = getCommonHeader(buffer);
        if (_header.ctrl) {
            if (_header.control.version == SPDY_VERSION) {
                _type = (SPDYControlFrameType) _header.control.type;
                _length = _header.length;
                _state = READ_CONTROL_FRAME;
            } else {
                _state = FRAME_ERROR;
            }
        } else {
            _length = _header.length;
            _state = READ_DATA_FRAME;
        }

        return SPDY_COMMON_HEADER_SIZE;
    } else {
        return 0;
    }
}

- (NSUInteger)_readControlFrame:(uint8_t *)buffer length:(NSUInteger)len
{
    NSUInteger bytesRead = 0;
    NSUInteger minLength;

    switch (_type) {

        /* Header block frames */

        case SPDY_SYN_STREAM_FRAME:
            minLength = 10;
            if (minLength <= len) {
                SPDYSynStreamFrame *frame =
                    [[SPDYSynStreamFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];

                frame.last = _header.flags & SPDY_FLAG_FIN;
                frame.unidirectional = _header.flags & SPDY_FLAG_UNIDIRECTIONAL;

                frame.streamId = getUnsignedInt31(buffer);
                frame.associatedToStreamId = getUnsignedInt31(buffer+4);
                frame.priority = buffer[8] >> 5 & (uint8_t)0x07;

                bytesRead = minLength;

                _headerBlockFrame = frame;
                _state = READ_HEADER_BLOCK;
            }
            break;

        case SPDY_SYN_REPLY_FRAME:
            minLength = 4;
            if (minLength <= len) {
                SPDYSynReplyFrame *frame =
                    [[SPDYSynReplyFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];

                frame.last = _header.flags & SPDY_FLAG_FIN;
                frame.streamId = getUnsignedInt31(buffer);
                bytesRead = minLength;

                _headerBlockFrame = frame;
                _state = READ_HEADER_BLOCK;
            }
            break;

        case SPDY_HEADERS_FRAME:
            minLength = 4;
            if (minLength <= len) {
                SPDYHeadersFrame *frame =
                    [[SPDYHeadersFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];

                frame.last = _header.flags & SPDY_FLAG_FIN;
                frame.streamId = getUnsignedInt31(buffer);
                bytesRead = minLength;

                _headerBlockFrame = frame;
                _state = READ_HEADER_BLOCK;
            }
            break;

        /* Settings frame */

        case SPDY_SETTINGS_FRAME:
            minLength = 4;
            if (minLength <= len) {
                SPDYSettingsFrame *frame =
                    [[SPDYSettingsFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];
                frame.clearSettings = _header.flags & SPDY_SETTINGS_FLAG_CLEAR_SETTINGS;

                NSUInteger settingsCount = getUnsignedInt32(buffer);
                bytesRead = minLength;

                NSUInteger lengthRemaining = _length - bytesRead;

                // "gangnam-style" -JP
                if ((lengthRemaining & 0x07) != 0 || lengthRemaining >> 3 != settingsCount) {
                    _state = FRAME_ERROR;
                    return bytesRead;
                }

                _settingsFrame = frame;
                _state = READ_SETTINGS;
            }

            break;

        /* Fixed-length frames */

        case SPDY_RST_STREAM_FRAME:
            minLength = 8;
            if (minLength <= len) {
                SPDYRstStreamFrame *frame =
                    [[SPDYRstStreamFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];
                frame.streamId = getUnsignedInt31(buffer);
                frame.statusCode = (SPDYStreamStatus)getUnsignedInt32(buffer+4);
                bytesRead = minLength;
                [_delegate didReadRstStreamFrame:frame frameDecoder:self];
                _state = READ_COMMON_HEADER;
            }
            break;

        case SPDY_PING_FRAME:
            minLength = 4;
            if (minLength <= len) {
                SPDYPingFrame *frame =
                    [[SPDYPingFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];
                frame.pingId = getUnsignedInt32(buffer);
                bytesRead = minLength;
                [_delegate didReadPingFrame:frame frameDecoder:self];
                _state = READ_COMMON_HEADER;
            }
            break;

        case SPDY_GOAWAY_FRAME:
            minLength = 8;
            if (minLength <= len) {
                SPDYGoAwayFrame *frame =
                    [[SPDYGoAwayFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];
                frame.lastGoodStreamId = getUnsignedInt31(buffer);
                frame.statusCode = (SPDYSessionStatus)getUnsignedInt32(buffer+4);
                bytesRead = minLength;
                [_delegate didReadGoAwayFrame:frame frameDecoder:self];
                _state = READ_COMMON_HEADER;
            }
            break;

        case SPDY_WINDOW_UPDATE_FRAME:
            minLength = 8;
            if (minLength <= len) {
                SPDYWindowUpdateFrame *frame =
                    [[SPDYWindowUpdateFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];
                frame.streamId = getUnsignedInt31(buffer);
                frame.deltaWindowSize = getUnsignedInt31(buffer+4);
                bytesRead = minLength;
                [_delegate didReadWindowUpdateFrame:frame frameDecoder:self];
                _state = READ_COMMON_HEADER;

            }
            break;

        default:
            _state = FRAME_ERROR;
    }

    _length -= bytesRead;
    return bytesRead;
}

- (NSUInteger)_readDataFrame:(uint8_t *)buffer length:(NSUInteger)len
{
    SPDYStreamId streamId = _header.data.streamId;
    if (streamId == 0) {
        _state = FRAME_ERROR;
        return 0;
    }

    NSUInteger bytesToRead = MIN(len, _length);
    NSUInteger bytesRead = 0;

    // Skip production of non-terminating 0-length frames, in other words,
    // don't produce anything for now if we can't make progress and either
    // - this frame read is still incomplete
    // - or this is not the last frame on the stream
    if (bytesToRead == 0 && (_length > 0 || ((_header.flags & SPDY_DATA_FLAG_FIN) == 0))) {
        return 0;
    }

    SPDYDataFrame *frame = [[SPDYDataFrame alloc] initWithLength:SPDY_COMMON_HEADER_SIZE + _length];
    frame.streamId = streamId;
    frame.data = [[NSData alloc] initWithBytesNoCopy:buffer
                                              length:bytesToRead
                                        freeWhenDone:NO];

    bytesRead = bytesToRead;
    _length -= bytesToRead;

    if (_length == 0) {
        frame.last = ((_header.flags & SPDY_DATA_FLAG_FIN) != 0);
        _state = READ_COMMON_HEADER;
    }

    // The delegate is only guaranteed access to the NSData object on the frame
    // for the duration of this call. It has no ownership of the buffer and must
    // perform all processing or copy the data elsewhere prior to returning.
    [_delegate didReadDataFrame:frame frameDecoder:self];

    return bytesRead;
}

- (NSUInteger)_readHeaderBlock:(uint8_t *)buffer length:(NSUInteger)len
{
    NSUInteger bytesToRead = MIN(_length, len);
    NSUInteger bytesRead = 0;
    NSError *error = nil;

    _decompressedLength += [_decompressor inflate:buffer
                                          availIn:bytesToRead
                                     outputBuffer:(_decompressed + _decompressedLength)
                                         availOut:(_maxHeaderBlockLength - _decompressedLength)
                                            error:&error];


    bytesRead = bytesToRead;

    if (error) {
        _state = FRAME_ERROR;
        return bytesRead;
    }

    _length -= bytesRead;

    if (_length == 0) {
        if (_headerBlockFrame != nil) {
            NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
            NSUInteger headerNameLength, headerValueLength;

            if (_decompressedLength < 4) {
                _state = FRAME_ERROR;
                return bytesRead;
            }

            NSUInteger headerCount = getUnsignedInt32(_decompressed);
            NSUInteger bufferIndex = 4;

            while (headerCount > 0 && bufferIndex < _decompressedLength) {

                /* Read header name length */

                if (bufferIndex + 4 > _decompressedLength) {
                    _state = FRAME_ERROR;
                    return bytesRead;
                }

                headerNameLength = getUnsignedInt32(_decompressed + bufferIndex);
                bufferIndex += 4;

                /* Read header name */

                if (bufferIndex + headerNameLength > _decompressedLength) {
                    _state = FRAME_ERROR;
                    return bytesRead;
                }

                NSString *headerName = [[NSString alloc] initWithBytes:(_decompressed + bufferIndex) length:headerNameLength encoding:NSUTF8StringEncoding];
                bufferIndex += headerNameLength;

                /* Read header value length */

                if (bufferIndex + 4 > _decompressedLength) {
                    _state = FRAME_ERROR;
                    return bytesRead;
                }

                headerValueLength = getUnsignedInt32(_decompressed + bufferIndex);
                bufferIndex += 4;

                /* Read header value */

                if (bufferIndex + headerValueLength > _decompressedLength) {
                    _state = FRAME_ERROR;
                    return bytesRead;
                }

                NSString *headerValue = [[NSString alloc] initWithBytes:(_decompressed + bufferIndex) length:headerValueLength encoding:NSUTF8StringEncoding];
                bool arrayValue = NO;
                for (int i = 1; !arrayValue && i < headerValueLength - 1; i++) {
                    if (_decompressed[bufferIndex + i] == '\0') {
                        arrayValue = YES;
                    }
                }
                bufferIndex += headerValueLength;

                if (arrayValue) {
                    headers[headerName] = [headerValue componentsSeparatedByString:@"\0"];
                } else {
                    headers[headerName] = headerValue;
                }

                headerCount--;
            }

            if (headerCount > 0 || bufferIndex < _decompressedLength) {
                _state = FRAME_ERROR;
                return bytesRead;
            }

            _headerBlockFrame.headers = headers;

            switch (_type) {
                case SPDY_SYN_STREAM_FRAME:
                    [_delegate didReadSynStreamFrame:(SPDYSynStreamFrame *) _headerBlockFrame frameDecoder:self];
                    break;
                case SPDY_SYN_REPLY_FRAME:
                    [_delegate didReadSynReplyFrame:(SPDYSynReplyFrame *) _headerBlockFrame frameDecoder:self];
                    break;
                case SPDY_HEADERS_FRAME:
                    [_delegate didReadHeadersFrame:(SPDYHeadersFrame *) _headerBlockFrame frameDecoder:self];
                    break;
                default:
                    // Should never happen
                    break;
            }
        }

        _decompressedLength = 0;
        _state = READ_COMMON_HEADER;
    }

    return bytesRead;
}

- (NSUInteger)_readSettings:(uint8_t *)buffer length:(NSUInteger)len
{
    NSUInteger bytesToRead = MIN(_length, len);
    NSUInteger bytesRead = 0;

    while (bytesRead + 8 <= bytesToRead) {
        uint8_t flags = buffer[bytesRead];
        SPDYSettingsId settingsId = (SPDYSettingsId)getUnsignedInt24(buffer + bytesRead);
        bytesRead += 4;

        int32_t value = getSignedInt32(buffer + bytesRead);
        bytesRead += 4;

        if (settingsId >= _SPDY_SETTINGS_RANGE_START && settingsId < _SPDY_SETTINGS_RANGE_END && !_settingsFrame.settings[settingsId].set) {
            _settingsFrame.settings[settingsId].set = YES;
            _settingsFrame.settings[settingsId].flags = flags;
            _settingsFrame.settings[settingsId].value = value;
        }
    }

    _length -= bytesRead;

    if (_length == 0) {
        [_delegate didReadSettingsFrame:_settingsFrame frameDecoder:self];
        _state = READ_COMMON_HEADER;
    }

    return bytesRead;
}

@end
