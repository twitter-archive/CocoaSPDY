//
//  SPDYMetadata.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore
//


#import <Foundation/Foundation.h>
#import "SPDYDefinitions.h"

@interface SPDYMetadata : NSObject
@property (nonatomic) NSString *version;
@property (assign) SPDYStreamId streamId;
@property (assign) NSInteger latencyMs;
@property (assign) NSUInteger txBytes;
@property (assign) NSUInteger rxBytes;
@property (assign) bool cellular;

- (NSDictionary *)dictionary;
@end
