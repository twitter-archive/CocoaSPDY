//
//  SPDYSettingsStore.h
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

@class SPDYOrigin;

@interface SPDYSettingsStore : NSObject
+ (SPDYSettings *)settingsForOrigin:(SPDYOrigin *)origin;
+ (void)persistSettings:(SPDYSettings *)settings forOrigin:(SPDYOrigin *)origin;
+ (void)clearSettingsForOrigin:(SPDYOrigin *)origin;
@end
