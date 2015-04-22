//
//  SPDYProtocol+Project.h
//  SPDY
//
//  Created by Nolan O'Brien on 4/17/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <SPDY/SPDYProtocol.h>

@interface SPDYProtocol (Project)

@property (nonatomic, readonly) NSURLSession *associatedSession;
@property (nonatomic, readonly) NSURLSessionTask *associatedSessionTask;

@end
