//
//  SPDYFrameEncoderAccumulator.h
//  SPDY
//
//  Created by Klemen Verdnik on 6/10/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPDYFrameEncoder.h"

@interface SPDYFrameEncoderAccumulator : NSObject <SPDYFrameEncoderDelegate>

@property (nonatomic) NSData *lastEncodedData;

@end
