//
//  SPDYFrameDecoder.h
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

@class SPDYFrameDecoder;

@protocol SPDYFrameDecoderDelegate <NSObject>

- (void)didReadDataFrame:(SPDYDataFrame *)dataFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)didReadSynStreamFrame:(SPDYSynStreamFrame *)synStreamFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)didReadSynReplyFrame:(SPDYSynReplyFrame *)synReplyFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)didReadRstStreamFrame:(SPDYRstStreamFrame *)rstStreamFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)didReadSettingsFrame:(SPDYSettingsFrame *)settingsFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)didReadPingFrame:(SPDYPingFrame *)pingFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)didReadGoAwayFrame:(SPDYGoAwayFrame *)goAwayFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)didReadHeadersFrame:(SPDYHeadersFrame *)headersFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;
- (void)didReadWindowUpdateFrame:(SPDYWindowUpdateFrame *)windowUpdateFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder;

@end

@interface SPDYFrameDecoder : NSObject
@property (nonatomic, weak) id<SPDYFrameDecoderDelegate> delegate;

- (id)initWithDelegate:(id<SPDYFrameDecoderDelegate>)delegate;

// returns the number of bytes consumed; the caller is responsible for accumulating unprocessed bytes
- (NSUInteger)decode:(uint8_t *)buffer length:(NSUInteger)len error:(NSError **)pError;

@end
