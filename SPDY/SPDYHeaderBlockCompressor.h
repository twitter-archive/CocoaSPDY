//
//  SPDYHeaderBlockCompressor.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>

@interface SPDYHeaderBlockCompressor : NSObject
- (id)initWithCompressionLevel:(NSUInteger)compressionLevel;
- (NSUInteger)deflate:(uint8_t *)inputBuffer availIn:(NSUInteger)inputLength outputBuffer:(uint8_t *)outputBuffer availOut:(NSUInteger)outputLength error:(NSError **)pError;
@end
