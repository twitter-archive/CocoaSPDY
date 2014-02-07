//
//  SPDYHeaderBlockDecompressor.h
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

#import "SPDYHeaderBlockDecompressor.h"
#import "SPDYError.h"
#import "SPDYZLibCommon.h"

@implementation SPDYHeaderBlockDecompressor
{
    z_stream _zlibStream;
    int _zlibStreamStatus;
}

- (id)init
{
    self = [super init];
    if (self) {
        bzero(&_zlibStream, sizeof(_zlibStream));

        _zlibStream.zalloc   = Z_NULL;
        _zlibStream.zfree    = Z_NULL;
        _zlibStream.opaque   = Z_NULL;

        _zlibStream.avail_in = 0;
        _zlibStream.next_in  = Z_NULL;

        _zlibStreamStatus = inflateInit(&_zlibStream);
        NSAssert(_zlibStreamStatus == Z_OK, @"unable to initialize zlib stream");
    }
    return self;
}

- (void)dealloc
{
    inflateEnd(&_zlibStream);
}

// Always consumes ALL available input or sets an error, and returns the number of bytes written to the output buffer.
- (NSUInteger)inflate:(uint8_t *)inputBuffer availIn:(NSUInteger)inputLength outputBuffer:(uint8_t *)outputBuffer availOut:(NSUInteger)outputLength error:(NSError **)pError
{
    if (_zlibStreamStatus != Z_OK) {
        if (pError) *pError = SPDY_CODEC_ERROR(SDPYHeaderBlockDecodingError, @"invalid zlib stream state");
        return 0;
    }

    _zlibStream.next_in = inputBuffer;
    _zlibStream.avail_in = (uInt)inputLength;

    _zlibStream.next_out = outputBuffer;
    _zlibStream.avail_out = (uInt)outputLength;

    while (_zlibStream.avail_in > 0 && !*pError) {
        _zlibStreamStatus = inflate(&_zlibStream, Z_SYNC_FLUSH);

        switch (_zlibStreamStatus) {
            case Z_NEED_DICT:
                // We can't set the dictionary ahead of time due to zlib funkiness.
                _zlibStreamStatus = inflateSetDictionary(&_zlibStream, kSPDYDict, sizeof(kSPDYDict));
                NSAssert(_zlibStreamStatus == Z_OK, @"unable to set zlib dictionary");
                break;

            case Z_STREAM_END:
                break;

            case Z_BUF_ERROR:
            case Z_OK:
                // For simplicity's sake, if avail_out == 0, we treat the header block
                // as too large for this implementation to handle.
                if (_zlibStream.avail_out == 0) {
                    *pError = SPDY_CODEC_ERROR(SDPYHeaderBlockDecodingError, @"header block is too large");
                }
                break;

            case Z_STREAM_ERROR:
            case Z_DATA_ERROR:
            case Z_MEM_ERROR:
                *pError = SPDY_CODEC_ERROR(SDPYHeaderBlockDecodingError, @"error decompressing header block");
                break;
        }
    }

    return _zlibStream.next_out - outputBuffer;
}

@end
