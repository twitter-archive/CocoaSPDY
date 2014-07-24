//
//  SPDYFrameEncoder.m
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

#import "SPDYError.h"
#import "SPDYFrameEncoder.h"
#import "SPDYHeaderBlockCompressor.h"

@interface SPDYFrameEncoder ()
- (bool)_encodeHeaders:(NSDictionary *)dictionary error:(NSError **)pError;
- (bool)_writeUInt32:(uint32_t)value error:(NSError **)pError;
- (bool)_writeString:(NSString*)value error:(NSError **)pError;
@end

@implementation SPDYFrameEncoder
{
    SPDYHeaderBlockCompressor *_compressor;
    NSUInteger _encodedHeadersLength;
    NSUInteger _compressedLength;
    uint8_t *_encodedHeaders;
    uint8_t *_compressed;
}

- (id)initWithDelegate:(id<SPDYFrameEncoderDelegate>)delegate headerCompressionLevel:(NSUInteger)headerCompressionLevel
{
    self = [super init];
    if (self) {
        _delegate = delegate;

        _compressor = [[SPDYHeaderBlockCompressor alloc] initWithCompressionLevel:headerCompressionLevel];
        _encodedHeaders = malloc(sizeof(uint8_t) * MAX_HEADER_BLOCK_LENGTH);
        _compressed = malloc(sizeof(uint8_t) * MAX_COMPRESSED_HEADER_BLOCK_LENGTH);
        _encodedHeadersLength = 0;
        _compressedLength = 0;
    }
    return self;
}

- (void)dealloc
{
    free(_encodedHeaders);
    free(_compressed);
}

- (bool)encodeDataFrame:(SPDYDataFrame *)dataFrame
{
    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:8];

    uint32_t streamId = htonl(dataFrame.streamId);
    uint32_t flags = SPDY_DATA_FLAG_FIN * dataFrame.last;
    uint32_t flags_length = htonl(flags << 24 | (uint32_t)dataFrame.data.length);

    [encodedData appendBytes:&streamId length:4];
    [encodedData appendBytes:&flags_length length:4];

    [_delegate didEncodeData:encodedData frameEncoder:self];
    [_delegate didEncodeData:dataFrame.data frameEncoder:self];
    return YES;
}

- (bool)encodeSynStreamFrame:(SPDYSynStreamFrame *)synStreamFrame error:(NSError**)pError
{
    if (![self _encodeHeaders:synStreamFrame.headers error:pError]) {
        return NO;
    }

    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:18 + _compressedLength];

    uint8_t control = 0x80;
    uint8_t version = 3;
    uint16_t type = htons(SPDY_SYN_STREAM_FRAME);
    uint32_t flags = SPDY_FLAG_FIN * synStreamFrame.last | SPDY_FLAG_UNIDIRECTIONAL * synStreamFrame.unidirectional;
    uint32_t flags_length = htonl(flags << 24 | 10 + _compressedLength);
    uint32_t streamId = htonl(synStreamFrame.streamId);
    uint32_t assocStreamId = htonl(synStreamFrame.associatedToStreamId);
    uint16_t priority_slot = htons((uint16_t)synStreamFrame.priority << 13);

    [encodedData appendBytes:&control length:1];
    [encodedData appendBytes:&version length:1];
    [encodedData appendBytes:&type length:2];
    [encodedData appendBytes:&flags_length length:4];
    [encodedData appendBytes:&streamId length:4];
    [encodedData appendBytes:&assocStreamId length:4];
    [encodedData appendBytes:&priority_slot length:2];
    [encodedData appendBytes:_compressed length:_compressedLength];

    [_delegate didEncodeData:encodedData frameEncoder:self];
    return YES;
}

- (bool)encodeSynReplyFrame:(SPDYSynReplyFrame *)synReplyFrame error:(NSError**)pError
{
    if (![self _encodeHeaders:synReplyFrame.headers error:pError]) {
        return NO;
    }

    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:12 + _compressedLength];

    uint8_t control = 0x80;
    uint8_t version = 3;
    uint16_t type = htons(SPDY_SYN_REPLY_FRAME);
    uint32_t flags = SPDY_FLAG_FIN * synReplyFrame.last;
    uint32_t flags_length = htonl(flags << 24 | 4 + _compressedLength);
    uint32_t streamId = htonl(synReplyFrame.streamId);

    [encodedData appendBytes:&control length:1];
    [encodedData appendBytes:&version length:1];
    [encodedData appendBytes:&type length:2];
    [encodedData appendBytes:&flags_length length:4];
    [encodedData appendBytes:&streamId length:4];
    [encodedData appendBytes:_compressed length:_compressedLength];

    [_delegate didEncodeData:encodedData frameEncoder:self];
    return YES;
}

- (bool)encodeRstStreamFrame:(SPDYRstStreamFrame *)rstStreamFrame
{
    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:16];

    uint8_t control = 0x80;
    uint8_t version = 3;
    uint16_t type = htons(SPDY_RST_STREAM_FRAME);
    uint32_t flags_length = htonl(8); // no flags
    uint32_t streamId = htonl(rstStreamFrame.streamId);
    uint32_t statusCode = htonl(rstStreamFrame.statusCode);

    [encodedData appendBytes:&control length:1];
    [encodedData appendBytes:&version length:1];
    [encodedData appendBytes:&type length:2];
    [encodedData appendBytes:&flags_length length:4];
    [encodedData appendBytes:&streamId length:4];
    [encodedData appendBytes:&statusCode length:4];

    [_delegate didEncodeData:encodedData frameEncoder:self];
    return YES;
}

- (bool)encodeSettingsFrame:(SPDYSettingsFrame *)settingsFrame
{
    uint32_t numEntries = 0;

    SPDY_SETTINGS_ITERATOR(i) {
        if (settingsFrame.settings[i].set) {
            numEntries++;
        }
    }

    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:(12 + 8 * numEntries)];

    uint8_t control = 0x80;
    uint8_t version = 3;
    uint16_t type = htons(SPDY_SETTINGS_FRAME);
    uint32_t flags = SPDY_SETTINGS_FLAG_CLEAR_SETTINGS * settingsFrame.clearSettings;
    uint32_t flags_length = htonl(flags << 24 | 4 + 8 * numEntries);
    numEntries = htonl(numEntries);

    [encodedData appendBytes:&control length:1];
    [encodedData appendBytes:&version length:1];
    [encodedData appendBytes:&type length:2];
    [encodedData appendBytes:&flags_length length:4];
    [encodedData appendBytes:&numEntries length:4];

    SPDY_SETTINGS_ITERATOR(i) {
        if (settingsFrame.settings[i].set) {
            uint32_t flags_entryId = htonl((uint32_t)settingsFrame.settings[i].flags << 24 | i);
            uint32_t entryValue = htonl(settingsFrame.settings[i].value);
            [encodedData appendBytes:&flags_entryId length:4];
            [encodedData appendBytes:&entryValue length:4];
        }
    }

    [_delegate didEncodeData:encodedData frameEncoder:self];
    return YES;
}

- (bool)encodePingFrame:(SPDYPingFrame *)pingFrame
{
    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:12];

    uint8_t control = 0x80;
    uint8_t version = 3;
    uint16_t type = htons(SPDY_PING_FRAME);
    uint32_t flags_length = htonl(4); // no flags
    uint32_t pingId = htonl(pingFrame.pingId);

    [encodedData appendBytes:&control length:1];
    [encodedData appendBytes:&version length:1];
    [encodedData appendBytes:&type length:2];
    [encodedData appendBytes:&flags_length length:4];
    [encodedData appendBytes:&pingId length:4];

    [_delegate didEncodeData:encodedData withTag:pingFrame.pingId frameEncoder:self];
    return YES;
}

- (bool)encodeGoAwayFrame:(SPDYGoAwayFrame *)goAwayFrame
{
    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:1];

    uint8_t control = 0x80;
    uint8_t version = 3;
    uint16_t type = htons(SPDY_GOAWAY_FRAME);
    uint32_t flags_length = htonl(8); // no flags
    uint32_t lastGoodStreamId = htonl(goAwayFrame.lastGoodStreamId);
    uint32_t statusCode = htonl(goAwayFrame.statusCode);

    [encodedData appendBytes:&control length:1];
    [encodedData appendBytes:&version length:1];
    [encodedData appendBytes:&type length:2];
    [encodedData appendBytes:&flags_length length:4];
    [encodedData appendBytes:&lastGoodStreamId length:4];
    [encodedData appendBytes:&statusCode length:4];

    [_delegate didEncodeData:encodedData frameEncoder:self];
    return YES;
}

- (bool)encodeHeadersFrame:(SPDYHeadersFrame *)headersFrame error:(NSError **)pError
{
    if (![self _encodeHeaders:headersFrame.headers error:pError]) {
        return NO;
    }

    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:12 + _compressedLength];

    uint8_t control = 0x80;
    uint8_t version = 3;
    uint16_t type = htons(SPDY_HEADERS_FRAME);
    uint32_t flags = SPDY_FLAG_FIN * headersFrame.last;
    uint32_t flags_length = htonl(flags << 24 | 4 + _compressedLength);
    uint32_t streamId = htonl(headersFrame.streamId);

    [encodedData appendBytes:&control length:1];
    [encodedData appendBytes:&version length:1];
    [encodedData appendBytes:&type length:2];
    [encodedData appendBytes:&flags_length length:4];
    [encodedData appendBytes:&streamId length:4];
    [encodedData appendBytes:_compressed length:_compressedLength];

    [_delegate didEncodeData:encodedData frameEncoder:self];
    return YES;
}

- (bool)encodeWindowUpdateFrame:(SPDYWindowUpdateFrame *)windowUpdateFrame
{
    NSMutableData *encodedData = [[NSMutableData alloc] initWithCapacity:16];

    uint8_t control = 0x80;
    uint8_t version = 3;
    uint16_t type = htons(SPDY_WINDOW_UPDATE_FRAME);
    uint32_t flags_length = htonl(8); // no flags
    uint32_t streamId = htonl(windowUpdateFrame.streamId);
    uint32_t windowDelta = htonl(windowUpdateFrame.deltaWindowSize);

    [encodedData appendBytes:&control length:1];
    [encodedData appendBytes:&version length:1];
    [encodedData appendBytes:&type length:2];
    [encodedData appendBytes:&flags_length length:4];
    [encodedData appendBytes:&streamId length:4];
    [encodedData appendBytes:&windowDelta length:4];

    [_delegate didEncodeData:encodedData frameEncoder:self];
    return YES;
}

#pragma mark private methods

- (bool)_encodeHeaders:(NSDictionary *)headers error:(NSError **)pError
{
    _encodedHeadersLength = 0;
    _compressedLength = 0;

    if (![self _writeUInt32:(uint32_t)headers.count error:pError]) return NO;

    for (NSString *headerName in headers) {
        if (![self _writeUInt32:(uint32_t)headerName.length error:pError]) return NO;
        if (![self _writeString:headerName error:pError]) return NO;

        NSString *headerValue;

        if ([headers[headerName] isKindOfClass:[NSString class]]) {
            headerValue = headers[headerName];
        } else if ([headers[headerName] isKindOfClass:[NSArray class]]) {
            headerValue = [headers[headerName] componentsJoinedByString:@"\0"];
        }

        if (![self _writeUInt32:(uint32_t)headerValue.length error:pError]) return NO;
        if (![self _writeString:headerValue error:pError]) return NO;
    }

    _compressedLength = [_compressor deflate:_encodedHeaders
                                     availIn:_encodedHeadersLength
                                outputBuffer:_compressed
                                    availOut:MAX_COMPRESSED_HEADER_BLOCK_LENGTH
                                       error:pError];
    return (pError == nil || *pError == nil);
}

- (bool)_writeUInt32:(uint32_t)value error:(NSError **)pError
{
    if (_encodedHeadersLength + sizeof(uint32_t) > MAX_HEADER_BLOCK_LENGTH) {
        if (pError) {
            NSString *message = [NSString stringWithFormat:@"encoded headers exceeds %d bytes",
                                                           MAX_HEADER_BLOCK_LENGTH];
            *pError = SPDY_CODEC_ERROR(SDPYHeaderBlockEncodingError, message);
        }
        return NO;
    }
    *((uint32_t *)(_encodedHeaders + _encodedHeadersLength)) = htonl(value);
    _encodedHeadersLength += sizeof(uint32_t);
    return YES;
}

- (bool)_writeString:(NSString*)value error:(NSError **)pError
{
    NSRange leftover;
    NSUInteger used;

    [value getBytes:(_encodedHeaders + _encodedHeadersLength)
          maxLength:(MAX_HEADER_BLOCK_LENGTH - _encodedHeadersLength)
         usedLength:&used
           encoding:NSUTF8StringEncoding
            options:NSStringEncodingConversionAllowLossy
              range:NSMakeRange(0, value.length)
     remainingRange:&leftover];

    _encodedHeadersLength += used;

    if (leftover.length > 0) {
        if (pError) {
            NSString *message = [NSString stringWithFormat:@"encoded headers exceeds %d bytes",
                                                           MAX_HEADER_BLOCK_LENGTH];
            *pError = SPDY_CODEC_ERROR(SDPYHeaderBlockEncodingError, message);
        }
        return NO;
    }

    return YES;
}

@end
