//
//  SPDYStreamManager.h
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

@class SPDYProtocol;
@class SPDYStream;

/**
  Data structure for management of SPDYStreams.
*/
@interface SPDYStreamManager : NSObject <NSFastEnumeration>

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSUInteger localCount;
@property (nonatomic, readonly) NSUInteger remoteCount;
- (void)addStream:(SPDYStream *)stream;
- (id)objectAtIndexedSubscript:(NSUInteger)idx;
- (id)objectForKeyedSubscript:(id)key;
- (SPDYStream *)nextPriorityStream;
- (void)setObject:(id)obj atIndexedSubscript:(NSUInteger)idx;
- (void)removeStreamWithStreamId:(SPDYStreamId)streamId;
- (void)removeStreamForProtocol:(SPDYProtocol *)protocol;
- (void)removeAllStreams;

@end
