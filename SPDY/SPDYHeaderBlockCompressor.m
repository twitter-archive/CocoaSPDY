//
//  SPDYHeaderBlockCompressor.m
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

#import "SPDYHeaderBlockCompressor.h"
#import "SPDYError.h"
#import "SPDYZLibCommon.h"

// See https://groups.google.com/group/spdy-dev/browse_thread/thread/dfaf498542fac792
#define ZLIB_COMPRESSION_LEVEL 9
#define ZLIB_WINDOW_SIZE 11
#define ZLIB_MEMORY_LEVEL 1

@implementation SPDYHeaderBlockCompressor
{
    z_stream _zlibStream;
    int _zlibStreamStatus;
}

- (id)init
{
    return [self initWithCompressionLevel:ZLIB_COMPRESSION_LEVEL];
}

- (id)initWithCompressionLevel:(NSUInteger)compressionLevel
{
    self = [super init];
    if (self) {
        bzero(&_zlibStream, sizeof(_zlibStream));

        _zlibStream.zalloc   = Z_NULL;
        _zlibStream.zfree    = Z_NULL;
        _zlibStream.opaque   = Z_NULL;

        _zlibStream.avail_in = 0;
        _zlibStream.next_in  = Z_NULL;

        _zlibStreamStatus = deflateInit2(&_zlibStream, compressionLevel, Z_DEFLATED, ZLIB_WINDOW_SIZE, ZLIB_MEMORY_LEVEL, Z_DEFAULT_STRATEGY);
        NSAssert(_zlibStreamStatus == Z_OK, @"unable to initialize zlib stream");

        _zlibStreamStatus = deflateSetDictionary(&_zlibStream, kSPDYDict, sizeof(kSPDYDict));
        NSAssert(_zlibStreamStatus == Z_OK, @"unable to set zlib dictionary");
    }
    return self;
}

- (void)dealloc
{
    (void)deflateEnd(&_zlibStream);
}

// Always consumes ALL available input or sets an error, and returns the number of bytes written to the output buffer.
- (NSUInteger)deflate:(uint8_t *)inputBuffer availIn:(NSUInteger)inputLength outputBuffer:(uint8_t *)outputBuffer availOut:(NSUInteger)outputLength error:(NSError **)pError
{
    if (_zlibStreamStatus != Z_OK) {
        if (pError) *pError = SPDY_CODEC_ERROR(SDPYHeaderBlockEncodingError, @"invalid zlib stream state");
        return 0;
    }

    _zlibStream.next_in = inputBuffer;
    _zlibStream.avail_in = (uInt)inputLength;

    _zlibStream.next_out = outputBuffer;
    _zlibStream.avail_out = (uInt)outputLength;

    _zlibStreamStatus = deflate(&_zlibStream, Z_SYNC_FLUSH);

    if (_zlibStreamStatus != Z_OK && pError) {
        *pError = SPDY_CODEC_ERROR(SDPYHeaderBlockEncodingError, @"error compressing header block");
    }

    return _zlibStream.next_out - outputBuffer;
}

@end
