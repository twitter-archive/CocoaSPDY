//
//  SPDYFrame.m
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

#import "SPDYFrame.h"

@implementation SPDYFrame

- (id)initWithLength:(NSUInteger)encodedLength
{
    self = [self init];
    if (self) {
        _encodedLength = encodedLength;
    }
    return self;
}

@end

@implementation SPDYHeaderBlockFrame
@end

@implementation SPDYDataFrame
@end

@implementation SPDYSynStreamFrame
@end

@implementation SPDYSynReplyFrame
@end

@implementation SPDYRstStreamFrame
@end

@implementation SPDYSettingsFrame
{
    SPDYSettings _settings[SPDY_SETTINGS_LENGTH];
}

- (id)init
{
    self = [super init];
    if (self) {
        SPDY_SETTINGS_ITERATOR(i) {
            _settings[i].set = NO;
        }
    }
    return self;
}

- (SPDYSettings *)settings
{
    return _settings;
}

@end

@implementation SPDYPingFrame
@end

@implementation SPDYGoAwayFrame
@end

@implementation SPDYHeadersFrame
@end

@implementation SPDYWindowUpdateFrame
@end
