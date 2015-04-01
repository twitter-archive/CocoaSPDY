//
//  SPDYMetadataUtils.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

@class SPDYMetadata;

@interface SPDYMetadataUtils : NSObject

+ (void)setMetadata:(SPDYMetadata *)metadata forAssociatedDictionary:(NSMutableDictionary *)dictionary;
+ (SPDYMetadata *)metadataForAssociatedDictionary:(NSDictionary *)dictionary;

@end
