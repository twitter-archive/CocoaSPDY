//
//  SPDYSocketOps.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import "SPDYCommonLogger.h"
#import "SPDYOrigin.h"
#import "SPDYSocketOps.h"

@implementation SPDYSocketReadOp

- (id)initWithData:(NSMutableData *)data
       startOffset:(NSUInteger)startOffset
         maxLength:(NSUInteger)maxLength
           timeout:(NSTimeInterval)timeout
       fixedLength:(NSUInteger)fixedLength
               tag:(long)tag
{
    self = [super init];
    if (self) {
        if (data) {
            _buffer = data;
            _startOffset = startOffset;
            _bufferOwner = NO;
            _originalBufferLength = data.length;
        } else {
            _buffer = [[NSMutableData alloc] initWithLength:MAX(0, fixedLength)];
            _startOffset = 0;
            _bufferOwner = YES;
            _originalBufferLength = 0;
        }

        _bytesRead = 0;
        _maxLength = maxLength;
        _timeout = timeout;
        _fixedLength = fixedLength;
        _tag = tag;
    }
    return self;
}

/**
  Returns the safe length of data that can be read relative to the buffer.
 */
- (NSUInteger)safeReadLength
{
    if (_fixedLength > 0) {
        return _fixedLength - _bytesRead;
    } else {
        NSUInteger result = READ_CHUNK_SIZE;

        if (_maxLength > 0) {
            result = MIN(result, (_maxLength - _bytesRead));
        }

        if (!_bufferOwner && _buffer.length == _originalBufferLength) {
            NSUInteger bufferSize = _buffer.length;
            NSUInteger bufferSpace = bufferSize - _startOffset - _bytesRead;

            if (bufferSpace > 0) {
                result = MIN(result, bufferSpace);
            }
        }

        return result;
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:
            @"<SPDYSocketReadOp: startOffset %lu, maxLength %lu, fixedLength %lu, timeout %lu, bytesRead %lu>",
            (unsigned long)_startOffset, (unsigned long)_maxLength, (unsigned long)_fixedLength, (unsigned long)_timeout, (unsigned long)_bytesRead];
}
@end


@implementation SPDYSocketProxyReadOp

- (id)initWithTimeout:(NSTimeInterval)timeout
{
    return [super initWithData:nil
                   startOffset:0
                     maxLength:0
                       timeout:timeout
                   fixedLength:PROXY_READ_SIZE
                           tag:0];
}

- (bool)tryParseResponse
{
    if (_bytesRead == 0) {
        return NO;
    }

    // Response will look something like the following. Note we ignore any additional headers.
    //   HTTP/1.1 200 Connection established\r\n
    //   <Optional headers>
    //   \r\n
    //
    // Assumptions:
    // - always ends in \r\n\r\n. No extra data.
    // - single space only for whitespace

    uint8_t const *buffer = _buffer.mutableBytes + _startOffset;
    NSUInteger bufferLength = _bytesRead;
    const NSUInteger minimumValidResponseSize = 7;  // "A 1\r\n\r\n"
    NSUInteger index = 0;

    if (bufferLength < minimumValidResponseSize ||
            buffer[bufferLength - 4] != '\r' ||
            buffer[bufferLength - 3] != '\n' ||
            buffer[bufferLength - 2] != '\r' ||
            buffer[bufferLength - 1] != '\n') {
        return NO;
    }

    // We know buffer ends in "\r\n\r\n" so use '\r' as the terminator.

    NSUInteger versionStart = index;
    while (buffer[index] != ' ' && buffer[index] != '\r') {
        ++index;
    }
    if (index == versionStart) {
        return NO;
    }
    _version = [[NSString alloc] initWithBytesNoCopy:(void *)buffer length:index encoding:NSUTF8StringEncoding freeWhenDone:NO];

    NSUInteger statusCodeStart = ++index; // skip space
    while (buffer[index] != ' ' && buffer[index] != '\r') {
        ++index;
    }
    if (index == statusCodeStart) {
        return NO;
    }
    _statusCode = [[[NSString alloc] initWithBytesNoCopy:(void *)(buffer + statusCodeStart) length:(index - statusCodeStart) encoding:NSUTF8StringEncoding freeWhenDone:NO] integerValue];

    NSUInteger remainingStart = (buffer[index] == ' ') ? ++index : index; // skip space
    if ((bufferLength - remainingStart) < 4) {
        return NO;
    }
    _remaining = [[NSString alloc] initWithBytesNoCopy:(void *)(buffer + remainingStart) length:(bufferLength - remainingStart) encoding:NSUTF8StringEncoding freeWhenDone:NO];

    _bytesParsed = bufferLength;
    return YES;
}

- (bool)success
{
    return _statusCode >= 200 && _statusCode < 300 && [_version hasPrefix:@"HTTP/1"];
}

- (bool)needsAuth
{
    return _statusCode == 407 && [_version hasPrefix:@"HTTP/1"];
}

- (NSString *)description
{
    return [NSString stringWithFormat:
            @"<SPDYSocketProxyReadOp: fixedLength %lu, timeout %lu, bytesRead %lu, version %@, statusCode %lu>",
            (unsigned long)_fixedLength, (unsigned long)_timeout, (unsigned long)_bytesRead, _version, (unsigned long)_statusCode];
}

@end


@implementation SPDYSocketWriteOp

- (id)initWithData:(NSData *)data timeout:(NSTimeInterval)timeout tag:(long)tag
{
    self = [super init];
    if (self) {
        _buffer = data;
        _bytesWritten = 0;
        _timeout = timeout;
        _tag = tag;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:
            @"<SPDYSocketWriteOp: timeout %lu, tag %ld, size %lu, bytesWritten %lu>",
            (unsigned long)_timeout, _tag, (unsigned long)_buffer.length, (unsigned long)_bytesWritten];
}

@end


@implementation SPDYSocketProxyWriteOp

- (id)initWithOrigin:(SPDYOrigin *)origin timeout:(NSTimeInterval)timeout
{
    NSString *httpConnect = [NSString stringWithFormat:
            @"CONNECT %@:%u HTTP/1.1\r\nHost: %@:%u\r\nConnection: keep-alive\r\nUser-Agent: SPDYTest\r\n\r\n",
            origin.host,
            origin.port,
            origin.host,
            origin.port];
    NSData *httpConnectData = [httpConnect dataUsingEncoding:NSUTF8StringEncoding];
    self = [super initWithData:httpConnectData timeout:timeout tag:0];
    return self;
}

- (NSString *)description
{
    NSString *httpConnect = [[NSString alloc] initWithData:_buffer encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:
            @"<SPDYSocketProxyWriteOp: timeout %lu, tag %ld, size %lu, bytesWritten %lu> connect: %@",
            (unsigned long)_timeout, _tag, (unsigned long)_buffer.length, (unsigned long)_bytesWritten, httpConnect];
}

@end


@implementation SPDYSocketTLSOp

- (id)initWithTLSSettings:(NSDictionary *)settings
{
    self = [super init];
    if (self) {
        _tlsSettings = [settings copy];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<SPDYSocketTLSOp: settings %@>", _tlsSettings];
}

@end


