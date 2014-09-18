//
//  SPDYFrameEncoder.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>
#import "SPDYFrame.h"

// GZIP header is 12 bytes, so this is an upper bound on compressed size
#define COMPRESSED_FRAME_HEADER_LENGTH 12
#define MAX_HEADER_BLOCK_LENGTH (16384 - COMPRESSED_FRAME_HEADER_LENGTH)
#define MAX_COMPRESSED_HEADER_BLOCK_LENGTH (MAX_HEADER_BLOCK_LENGTH + COMPRESSED_FRAME_HEADER_LENGTH)

@class SPDYFrameEncoder;

@protocol SPDYFrameEncoderDelegate <NSObject>
- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder;
- (void)didEncodeData:(NSData *)data withTag:(uint32_t)tag frameEncoder:(SPDYFrameEncoder *)encoder;
@end

@interface SPDYFrameEncoder : NSObject
@property (nonatomic, weak) id<SPDYFrameEncoderDelegate> delegate;
- (id)initWithDelegate:(id <SPDYFrameEncoderDelegate>)delegate headerCompressionLevel:(NSUInteger)headerCompressionLevel;

// All of the encode methods return the number of bytes encoded, or -1 if an error occurred.
- (NSInteger)encodeDataFrame:(SPDYDataFrame *)dataFrame;
- (NSInteger)encodeSynStreamFrame:(SPDYSynStreamFrame *)synStreamFrame error:(NSError**)pError;
- (NSInteger)encodeSynReplyFrame:(SPDYSynReplyFrame *)synReplyFrame error:(NSError**)pError;
- (NSInteger)encodeRstStreamFrame:(SPDYRstStreamFrame *)rstStreamFrame;
- (NSInteger)encodeSettingsFrame:(SPDYSettingsFrame *)settingsFrame;
- (NSInteger)encodePingFrame:(SPDYPingFrame *)pingFrame;
- (NSInteger)encodeGoAwayFrame:(SPDYGoAwayFrame *)goAwayFrame;
- (NSInteger)encodeHeadersFrame:(SPDYHeadersFrame *)headersFrame error:(NSError**)pError;
- (NSInteger)encodeWindowUpdateFrame:(SPDYWindowUpdateFrame *)windowUpdateFrame;
@end
