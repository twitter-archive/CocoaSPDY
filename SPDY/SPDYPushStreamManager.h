//
//  SPDYPushStreamManager.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <Foundation/Foundation.h>

@class SPDYProtocol;
@class SPDYStream;

@interface SPDYPushStreamManager : NSObject

- (NSUInteger)pushStreamCount;
- (NSUInteger)associatedStreamCount;
- (SPDYStream *)streamForProtocol:(SPDYProtocol *)protocol;
- (void)addStream:(SPDYStream *)stream associatedWith:(SPDYStream *)associatedStream;
- (void)stopLoadingStream:(SPDYStream *)stream;

@end
