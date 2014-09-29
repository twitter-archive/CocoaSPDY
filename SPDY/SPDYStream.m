//
//  SPDYStream.m
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

#import <zlib.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYCommonLogger.h"
#import "SPDYError.h"
#import "SPDYProtocol.h"
#import "SPDYStream.h"
#import "SPDYMetadata.h"

#define DECOMPRESSED_CHUNK_LENGTH 8192
#define MIN_WRITE_CHUNK_LENGTH 4096
#define MAX_WRITE_CHUNK_LENGTH 131072
#define MAX_DISPATCH_ATTEMPTS 3
#define USE_CFSTREAM 0

#if USE_CFSTREAM
#define SCHEDULE_STREAM() [self _scheduleCFReadStream]
#define UNSCHEDULE_STREAM() [self _unscheduleCFReadStream]
#else
#define SCHEDULE_STREAM() [self _scheduleNSInputStream]
#define UNSCHEDULE_STREAM() [self _unscheduleNSInputStream]
#endif

@interface SPDYStream () <NSStreamDelegate>
- (void)_scheduleCFReadStream;
- (void)_unscheduleCFReadStream;
- (void)_scheduleNSInputStream;
- (void)_unscheduleNSInputStream;
@end

@implementation SPDYStream
{
    SPDYMetadata *_metadata;
    NSData *_data;
    NSString *_dataFile;
    NSInputStream *_dataStream;
    NSRunLoop *_runLoop;
    CFReadStreamRef _dataStreamRef;
    CFRunLoopRef _runLoopRef;
    NSUInteger _writeDataIndex;
    NSUInteger _writeStreamChunkLength;
    NSUInteger _dispatchAttempts;
    z_stream _zlibStream;
    bool _compressedResponse;
    bool _writeStreamOpened;
    int _zlibStreamStatus;
}

- (id)initWithProtocol:(SPDYProtocol *)protocol
{
    self = [super init];
    if (self) {
        _protocol = protocol;
        _client = protocol.client;
        _request = protocol.request;
        _priority = (uint8_t)MIN(_request.SPDYPriority, 0x07);
        _dispatchAttempts = 0;
        _local = YES;
        _localSideClosed = NO;
        _remoteSideClosed = NO;
        _compressedResponse = NO;
        _receivedReply = NO;
        _extendedDelegate = _request.SPDYDelegate;
        _metadata = [[SPDYMetadata alloc] init];
    }
    return self;
}

- (void)startWithStreamId:(SPDYStreamId)streamId sendWindowSize:(uint32_t)sendWindowSize receiveWindowSize:(uint32_t)receiveWindowSize
{
    _streamId = streamId;
    _metadata.streamId = streamId;
    _sendWindowSize = sendWindowSize;
    _receiveWindowSize = receiveWindowSize;
    _sendWindowSizeLowerBound = 0;
    _receiveWindowSizeLowerBound = 0;
    _writeDataIndex = 0;
    _writeStreamChunkLength = MIN_WRITE_CHUNK_LENGTH;

    if (_request.HTTPBody) {
        _data = _request.HTTPBody;
    } else if (_request.SPDYBodyFile) {
        _dataStream = [[NSInputStream alloc] initWithFileAtPath:_request.SPDYBodyFile];
    } else if (_request.HTTPBodyStream) {
        SPDY_WARNING(@"using HTTPBodyStream on a SPDY request is subject to a potentially fatal CFNetwork bug");
        _dataStream = _request.HTTPBodyStream;
    } else if (_request.SPDYBodyStream) {
        SPDY_WARNING(@"using SPDYBodyStream may fail for redirected requests or requests that meet authentication challenges");
        _dataStream = _request.SPDYBodyStream;
    }

    if (_dataStream) {
        _dataStreamRef = (__bridge CFReadStreamRef)_dataStream;
        SCHEDULE_STREAM();
    }
}

- (bool)reset
{
    // Requests that use an opaque NSInputStream cannot be reset once started
    // since no API exists to request a new stream
    if (_receivedReply ||
        _dispatchAttempts >= MAX_DISPATCH_ATTEMPTS ||
        (_streamId && _request.HTTPBodyStream)) {
        return NO;
    }

    _delegate = nil;
    if (_dataStream && (_runLoop || _runLoopRef)) {
        UNSCHEDULE_STREAM();
    }

    _streamId = 0;
    _localSideClosed = NO;
    _remoteSideClosed = NO;
    _dispatchAttempts += 1;

    return YES;
}

- (void)dealloc
{
    if (_compressedResponse) {
        inflateEnd(&_zlibStream);
    }

    if (_dataStream && (_runLoop || _runLoopRef)) {
        UNSCHEDULE_STREAM();
    }
}

- (void)setDataStream:(NSInputStream *)dataStream
{
    _dataStream = dataStream;
    _dataStreamRef = (__bridge CFReadStreamRef)dataStream;
}

- (void)cancel
{
    if (_delegate) [_delegate streamCanceled:self];
}

- (void)closeWithError:(NSError *)error
{
    _localSideClosed = YES;
    _remoteSideClosed = YES;

    if (_extendedDelegate &&
        [_extendedDelegate respondsToSelector:@selector(requestDidCompleteWithMetadata:)]) {
        [self _fireMetadataCallback];
    }

    if (_client) {
        // Failing to pass an error leads to null pointer exception
        if (!error) {
            error = SPDY_SOCKET_ERROR(SPDYSocketTransportError, @"Unknown socket error.");
        }
        [_client URLProtocol:_protocol didFailWithError:error];
    };

    if (_delegate && [_delegate respondsToSelector:@selector(streamClosed:)]) {
        [_delegate streamClosed:self];
    }
}

- (void)setLocalSideClosed:(bool)localSideClosed
{
    _localSideClosed = localSideClosed;

    if (_localSideClosed && _remoteSideClosed) {
        [self _close];
    }
}

- (void)setRemoteSideClosed:(bool)remoteSideClosed
{
    _remoteSideClosed = remoteSideClosed;

    if (_localSideClosed && _remoteSideClosed) {
        [self _close];
    }
}

- (void)_close
{
    if (_extendedDelegate &&
        [_extendedDelegate respondsToSelector:@selector(requestDidCompleteWithMetadata:)]) {
        [self _fireMetadataCallback];
    }

    if (_client) {
        [_client URLProtocolDidFinishLoading:_protocol];
    }

    if (_delegate && [_delegate respondsToSelector:@selector(streamClosed:)]) {
        [_delegate streamClosed:self];
    }
}

- (void)_fireMetadataCallback
{
    NSAssert(_request.SPDYDelegateRunLoop || _request.SPDYDelegateQueue,
             @"callback requires SPDYDelegateRunLoop or SPDYDelegateQueue to be set");

        void (^callback)(void) = ^{
            [_extendedDelegate requestDidCompleteWithMetadata:[_metadata dictionary]];
        };

        if (_request.SPDYDelegateRunLoop != nil) {
            CFRunLoopPerformBlock(
                [_request.SPDYDelegateRunLoop getCFRunLoop],
                (__bridge CFStringRef)_request.SPDYDelegateRunLoopMode,
                callback
            );
        } else if (_request.SPDYDelegateQueue != nil) {
            [_request.SPDYDelegateQueue addOperationWithBlock:callback];
        }
}

- (bool)closed
{
    return _localSideClosed && _remoteSideClosed;
}

- (bool)hasDataAvailable
{
    bool writeStreamAvailable = (
        _dataStream &&
        _writeStreamOpened &&
        _dataStream.streamStatus == NSStreamStatusOpen &&
        _dataStream.hasBytesAvailable
    );

    return (_data && _data.length - _writeDataIndex > 0) ||
        (writeStreamAvailable);
}

- (bool)hasDataPending
{
    bool writeStreamPending = (
        _dataStream &&
        (!_writeStreamOpened || _dataStream.streamStatus < NSStreamStatusAtEnd)
    );

    return (_data && _data.length - _writeDataIndex > 0) ||
        (writeStreamPending);
}

- (NSData *)readData:(NSUInteger)length error:(NSError **)pError
{
    if (_dataStream) {
        if (length > 0 && _dataStream.hasBytesAvailable) {
            NSUInteger maxLength = MIN(length, _writeStreamChunkLength);
            NSMutableData *writeData = [[NSMutableData alloc] initWithLength:maxLength];
            NSInteger bytesRead = [_dataStream read:(uint8_t *)writeData.bytes maxLength:maxLength];

            if (bytesRead > 0) {
                // If upstream window size is large enough to accommodate, progressively increase
                // the amount read with each pass, to balance memory usage against read calls.
                if (bytesRead == _writeStreamChunkLength) {
                    _writeStreamChunkLength = MIN(2 * _writeStreamChunkLength, MAX_WRITE_CHUNK_LENGTH);
                }

                writeData.length = (NSUInteger)bytesRead;
                return writeData;
            } else if (bytesRead < 0) {
                SPDY_DEBUG(@"SPDY stream read error");
                if (pError) {
                    NSDictionary *info = @{ NSLocalizedDescriptionKey: @"Unable to read request body stream" };
                    *pError = [[NSError alloc] initWithDomain:SPDYStreamErrorDomain
                                                         code:SPDYStreamCancel
                                                     userInfo:info];
                }
                _data = nil;
            }
        }
    } else if (_data) {
        length = MAX(MIN(_data.length - _writeDataIndex, length), 0);
        if (length == 0) return nil;

        uint8_t *bytes = ((uint8_t *)_data.bytes + _writeDataIndex);
        NSData *writeData = [[NSData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:NO];
        _writeDataIndex += length;

        return writeData;
    }

    return nil;
}

- (void)didReceiveResponse:(NSDictionary *)headers
{
    _receivedReply = YES;

    NSInteger statusCode = [headers[@":status"] intValue];
    if (statusCode < 100 || statusCode > 599) {
        NSDictionary *info = @{ NSLocalizedDescriptionKey: @"invalid http response code" };
        NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain
                                             code:NSURLErrorBadServerResponse
                                         userInfo:info];
        [self closeWithError:error];
        return;
    }

    NSString *version = headers[@":version"];
    if (!version) {
        NSDictionary *info = @{ NSLocalizedDescriptionKey: @"response missing version header" };
        NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain
                                             code:NSURLErrorBadServerResponse
                                         userInfo:info];
        [self closeWithError:error];
        return;
    }

    NSMutableDictionary *allHTTPHeaders = [[NSMutableDictionary alloc] init];
    for (NSString *key in headers) {
        if (![key hasPrefix:@":"]) {
            id headerValue = headers[key];
            if ([headerValue isKindOfClass:NSClassFromString(@"NSArray")]) {
                allHTTPHeaders[key] = [headers[key] componentsJoinedByString:@", "];
            } else {
                allHTTPHeaders[key] = headers[key];
            }
        }
    }

    NSURL *requestURL = _protocol.request.URL;

    if (_protocol.request.HTTPShouldHandleCookies) {
        NSString *httpSetCookie = allHTTPHeaders[@"set-cookie"];
        if (httpSetCookie) {
            // HTTP header field names are supposed to be case-insensitive, but
            // NSHTTPCookie will fail to automatically parse cookies unless we
            // force the case-senstive name "Set-Cookie"
            allHTTPHeaders[@"Set-Cookie"] = httpSetCookie;
            [allHTTPHeaders removeObjectForKey:@"set-cookie"];

            NSDictionary *cookieHeaders = @{ @"Set-Cookie": httpSetCookie };
            NSArray *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:cookieHeaders
                                                                      forURL:requestURL];

            [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies:cookies
                                                               forURL:requestURL
                                                      mainDocumentURL:_protocol.request.mainDocumentURL];
        }
    }

    NSString *encoding = allHTTPHeaders[@"content-encoding"];
    _compressedResponse = [encoding hasPrefix:@"deflate"] || [encoding hasPrefix:@"gzip"];
    if (_compressedResponse) {
        bzero(&_zlibStream, sizeof(_zlibStream));
        _zlibStreamStatus = inflateInit2(&_zlibStream, MAX_WBITS + 32);
    }

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:requestURL
                                                              statusCode:statusCode
                                                             HTTPVersion:version
                                                            headerFields:allHTTPHeaders];

    NSString *location = allHTTPHeaders[@"location"];

    if (location != nil) {
        NSURL *redirectURL = [[NSURL alloc] initWithString:location relativeToURL:requestURL];
        if (redirectURL == nil) {
            NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain
                                                 code:NSURLErrorRedirectToNonExistentLocation
                                             userInfo:nil];
            [self closeWithError:error];
            return;
        }

        NSMutableURLRequest *redirect = [_protocol.request mutableCopy];
        redirect.URL = redirectURL;
        redirect.SPDYPriority = _request.SPDYPriority;
        redirect.SPDYBodyFile = _request.SPDYBodyFile;

        if (statusCode == 303) {
            redirect.HTTPMethod = @"GET";
        }

        [_client URLProtocol:_protocol wasRedirectedToRequest:redirect redirectResponse:response];
        return;
    }

    [_client URLProtocol:_protocol
      didReceiveResponse:response
      cacheStoragePolicy:NSURLCacheStorageAllowed];
}

- (void)didLoadData:(NSData *)data
{
    NSUInteger dataLength = data.length;
    if (dataLength == 0) return;

    if (_compressedResponse) {
        _zlibStream.avail_in = (uInt)dataLength;
        _zlibStream.next_in = (uint8_t *)data.bytes;

        while (_zlibStreamStatus == Z_OK && (_zlibStream.avail_in > 0 || _zlibStream.avail_out == 0)) {
            uint8_t *inflatedBytes = malloc(sizeof(uint8_t) * DECOMPRESSED_CHUNK_LENGTH);
            if (inflatedBytes == NULL) {
                SPDY_ERROR(@"error decompressing response data: malloc failed");
                NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain
                                                     code:NSURLErrorCannotDecodeContentData
                                                 userInfo:nil];
                [self closeWithError:error];
                return;
            }

            _zlibStream.avail_out = DECOMPRESSED_CHUNK_LENGTH;
            _zlibStream.next_out = inflatedBytes;
            _zlibStreamStatus = inflate(&_zlibStream, Z_SYNC_FLUSH);

            NSMutableData *inflatedData = [[NSMutableData alloc] initWithBytesNoCopy:inflatedBytes length:DECOMPRESSED_CHUNK_LENGTH freeWhenDone:YES];
            NSUInteger inflatedLength = DECOMPRESSED_CHUNK_LENGTH - _zlibStream.avail_out;
            inflatedData.length = inflatedLength;
            if (inflatedLength > 0) {
                [_client URLProtocol:_protocol didLoadData:inflatedData];
            }

            // This can happen if the decompressed data is size N * DECOMPRESSED_CHUNK_LENGTH,
            // in which case we had to make an additional call to inflate() despite there being
            // no more input to ensure there wasn't any pending output in the zlib stream.
            if (_zlibStreamStatus == Z_BUF_ERROR) {
                _zlibStreamStatus = Z_OK;
                break;
            }
        }

        if (_zlibStreamStatus != Z_OK && _zlibStreamStatus != Z_STREAM_END) {
            SPDY_WARNING(@"error decompressing response data: bad z_stream state");
            NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain
                                                 code:NSURLErrorCannotDecodeContentData
                                             userInfo:nil];
            [self closeWithError:error];
            return;
        }
    } else {
        NSData *dataCopy = [[NSData alloc] initWithBytes:data.bytes length:dataLength];
        [_client URLProtocol:_protocol didLoadData:dataCopy];
    }
}

#pragma mark CFReadStreamClient

static void SPDYStreamCFReadStreamCallback(CFReadStreamRef stream, CFStreamEventType type, void *pStream)
{
    @autoreleasepool {
        SPDYStream * volatile spdyStream = (__bridge SPDYStream*)pStream;
        [spdyStream handleDataStreamEvent:type];
    }
}

- (void)handleDataStreamEvent:(CFStreamEventType)eventType
{
    if (eventType & kCFStreamEventOpenCompleted) {
        _writeStreamOpened = YES;
    } else if (!_writeStreamOpened) {
        return;
    }

    CFOptionFlags closeEvents = kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered;
    if (eventType & closeEvents) {
        [_delegate streamDataFinished:self];
    } else {
        [_delegate streamDataAvailable:self];
    }
}

#pragma mark NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    if (eventCode & NSStreamEventOpenCompleted) {
        _writeStreamOpened = YES;
    } else if (!_writeStreamOpened) {
        return;
    }

    if (_dataStream.streamStatus >= NSStreamStatusAtEnd) {
        [_delegate streamDataFinished:self];
    } else {
        [_delegate streamDataAvailable:self];
    }
}

#pragma mark private methods
- (void)_scheduleCFReadStream
{
    SPDY_DEBUG(@"scheduling CFReadStream: %p", _dataStreamRef);
    _runLoopRef = CFRunLoopGetCurrent();

    CFStreamClientContext clientContext;
    clientContext.version = 0;
    clientContext.info = (__bridge void *)(self);
    clientContext.retain = nil;
    clientContext.release = nil;
    clientContext.copyDescription = nil;

    CFOptionFlags readStreamEvents =
        kCFStreamEventHasBytesAvailable |
        kCFStreamEventErrorOccurred     |
        kCFStreamEventEndEncountered    |
        kCFStreamEventOpenCompleted;

    CFReadStreamClientCallBack clientCallback =
        (CFReadStreamClientCallBack)&SPDYStreamCFReadStreamCallback;

    if (!CFReadStreamSetClient(_dataStreamRef,
        readStreamEvents,
        clientCallback,
        &clientContext))
    {
        SPDY_ERROR(@"couldn't attach read stream to runloop");
        return;
    }

    CFReadStreamScheduleWithRunLoop(_dataStreamRef, _runLoopRef, kCFRunLoopDefaultMode);
    if (!CFReadStreamOpen(_dataStreamRef)) {
        SPDY_ERROR(@"can't open stream: %@", _dataStreamRef);
        return;
    }
}

- (void)_scheduleNSInputStream
{
    SPDY_DEBUG(@"scheduling NSInputStream: %@", _dataStream);
    _dataStream.delegate = self;
    _runLoop = [NSRunLoop currentRunLoop];
    [_dataStream scheduleInRunLoop:_runLoop forMode:NSDefaultRunLoopMode];
    [_dataStream open];
}

- (void)_unscheduleCFReadStream
{
    SPDY_DEBUG(@"unscheduling CFReadStream: %p", _dataStreamRef);
    CFReadStreamClose(_dataStreamRef);
    CFReadStreamSetClient(_dataStreamRef, kCFStreamEventNone, NULL, NULL);
    _runLoopRef = NULL;
}

- (void)_unscheduleNSInputStream
{
    SPDY_DEBUG(@"unscheduling NSInputStream: %@", _dataStream);
    [_dataStream close];
    _dataStream.delegate = nil;
    _runLoop = nil;
}

@end
