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

@class SPDYFrameEncoder;

@protocol SPDYFrameEncoderDelegate <NSObject>
- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder;
- (void)didEncodeData:(NSData *)data withTag:(uint32_t)tag frameEncoder:(SPDYFrameEncoder *)encoder;
@end

@interface SPDYFrameEncoder : NSObject
@property (nonatomic, weak) id<SPDYFrameEncoderDelegate> delegate;
- (id)initWithDelegate:(id <SPDYFrameEncoderDelegate>)delegate headerCompressionLevel:(NSUInteger)headerCompressionLevel;
- (bool)encodeDataFrame:(SPDYDataFrame *)dataFrame;
- (bool)encodeSynStreamFrame:(SPDYSynStreamFrame *)synStreamFrame;
- (bool)encodeSynReplyFrame:(SPDYSynReplyFrame *)synReplyFrame;
- (bool)encodeRstStreamFrame:(SPDYRstStreamFrame *)rstStreamFrame;
- (bool)encodeSettingsFrame:(SPDYSettingsFrame *)settingsFrame;
- (bool)encodePingFrame:(SPDYPingFrame *)pingFrame;
- (bool)encodeGoAwayFrame:(SPDYGoAwayFrame *)goAwayFrame;
- (bool)encodeHeadersFrame:(SPDYHeadersFrame *)headersFrame;
- (bool)encodeWindowUpdateFrame:(SPDYWindowUpdateFrame *)windowUpdateFrame;
@end
