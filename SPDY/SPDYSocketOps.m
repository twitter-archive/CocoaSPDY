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
    self = [super initWithData:nil
                   startOffset:0
                     maxLength:0
                       timeout:timeout
                   fixedLength:PROXY_READ_SIZE
                           tag:0];
    _statusCode = 0;
    return self;
}

- (bool)tryParseResponse
{
    if (_bytesRead == 0) {
        return NO;
    }

    // Response will look like:
    // HTTP/1.1 200 Connection established\r\n\r\n

    NSError *error = NULL;
    NSString *pattern = @"^([^ ]+) ([^ ]+) ([^ ]+.*)\\r\\n\\r\\n";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionDotMatchesLineSeparators
                                                                             error:&error];
    if (error) {
        SPDY_ERROR(@"regex error: %@", error);
        return NO;
    }

    NSString *response = [self responseAsString];
    __block NSUInteger count = 0;
    [regex enumerateMatchesInString:response
                            options:0
                              range:NSMakeRange(0, [response length])
                         usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
                             NSAssert(match.numberOfRanges == 4, nil);

                             if ([match rangeAtIndex:1].location != NSNotFound) {
                                 _version = [response substringWithRange:[match rangeAtIndex:1]];
                             }
                             if ([match rangeAtIndex:2].location != NSNotFound) {
                                 NSString *statusCode = [response substringWithRange:[match rangeAtIndex:2]];
                                 _statusCode = [statusCode integerValue];
                             }
                             if ([match rangeAtIndex:3].location != NSNotFound) {
                                 _statusMessage = [response substringWithRange:[match rangeAtIndex:3]];
                             }

                             _bytesParsed = [match range].length;
                             count++;
                         }];
    return count == 1;
}

- (NSString *)responseAsString
{
    void const *buffer = _buffer.mutableBytes + _startOffset;
    return [[NSString alloc] initWithBytes:buffer
                                    length:_bytesRead
                                  encoding:NSUTF8StringEncoding];

}

- (bool)success
{
    if (![_version isEqualToString:@"HTTP/1.0"] && ![_version isEqualToString:@"HTTP/1.1"]) {
        return NO;
    }
    if (_statusCode < 200 || _statusCode >= 300) {
        return NO;
    }
    if (_statusMessage.length == 0) {
        return NO;
    }

    return YES;
}

- (NSString *)description
{
    return [NSString stringWithFormat:
            @"<SPDYSocketProxyReadOp: fixedLength %lu, timeout %lu, bytesRead %lu, version %@, statusCode %lu, status %@>",
            (unsigned long)_fixedLength, (unsigned long)_timeout, (unsigned long)_bytesRead, _version, (unsigned long)_statusCode, _statusMessage];
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
            @"CONNECT %@:%u HTTP/1.1\r\nHost: %@\r\nConnection: keep-alive\r\nUser-Agent: SPDYTest\r\n\r\n",
            origin.host,
            origin.port,
            origin.host];
    NSData *httpConnectData = [httpConnect dataUsingEncoding:NSUTF8StringEncoding];
    self = [super initWithData:httpConnectData timeout:timeout tag:0];
    return self;
}

- (NSString *)description
{
    NSString *httpConnect = [[NSString alloc] initWithData:_buffer encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:
            @"<SPDYSocketProxyWriteOp: timeout %lu, tag %ld, bytesWritten %lu> connect: %@",
            (unsigned long)_timeout, _tag, (unsigned long)_bytesWritten, httpConnect];
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


