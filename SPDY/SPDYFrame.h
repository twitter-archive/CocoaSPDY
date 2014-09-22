//
//  SPDYFrame.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>
#import "SPDYDefinitions.h"

@interface SPDYFrame : NSObject
@property (nonatomic, assign) NSUInteger encodedLength;
- (id)initWithLength:(NSUInteger)encodedLength;
@end

@interface SPDYHeaderBlockFrame : SPDYFrame
@property (nonatomic, strong) NSDictionary *headers;
@end

@interface SPDYDataFrame : SPDYFrame
@property (nonatomic, strong) NSData *data;
@property (nonatomic) SPDYStreamId streamId;
@property (nonatomic) bool last;
@end

@interface SPDYSynStreamFrame : SPDYHeaderBlockFrame
@property (nonatomic) SPDYStreamId streamId;
@property (nonatomic) SPDYStreamId associatedToStreamId;
@property (nonatomic) uint8_t priority;
@property (nonatomic) uint8_t slot;
@property (nonatomic) bool last;
@property (nonatomic) bool unidirectional;
@end

@interface SPDYSynReplyFrame : SPDYHeaderBlockFrame
@property (nonatomic) SPDYStreamId streamId;
@property (nonatomic) bool last;
@end

@interface SPDYRstStreamFrame : SPDYFrame
@property (nonatomic) SPDYStreamId streamId;
@property (nonatomic) SPDYStreamStatus statusCode;
@end

@interface SPDYSettingsFrame : SPDYFrame
@property (nonatomic, readonly) SPDYSettings *settings;
@property (nonatomic) bool clearSettings;
@end

@interface SPDYPingFrame : SPDYFrame
@property (nonatomic) SPDYPingId pingId;
@end

@interface SPDYGoAwayFrame : SPDYFrame
@property (nonatomic) SPDYStreamId lastGoodStreamId;
@property (nonatomic) SPDYSessionStatus statusCode;
@end

@interface SPDYHeadersFrame : SPDYHeaderBlockFrame
@property (nonatomic) SPDYStreamId streamId;
@property (nonatomic) bool last;
@end

@interface SPDYWindowUpdateFrame : SPDYFrame
@property (nonatomic) SPDYStreamId streamId;
@property (nonatomic) uint32_t deltaWindowSize;
@end
