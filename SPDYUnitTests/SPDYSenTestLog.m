//
//  SPDYSentTestLog.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//
// The entire point of this file is to flush the code coverage .gcda files. Apple has a bug
// in their 7.x simulator, and possibly 8.0. At least, with Travis running 8.0, no .gcda files
// are generated without the flush. It works fine locally using the 8.1 simulator.
//
// See:
// http://www.cocoanetics.com/2013/10/xcode-coverage/
// http://stackoverflow.com/questions/19136767/generate-gcda-files-with-xcode5-ios7-simulator-and-xctest
// http://stackoverflow.com/questions/18394655/xcode5-code-coverage-from-cmd-line-for-ci-builds

// This is defined in the "Coverage" configuration.
#if COVERAGE

#import <SenTestingKit/SenTestingKit.h>

@interface SPDYSentTestLog : SenTestLog
@end

// GCOV Flush function
extern void __gcov_flush(void);

@implementation SPDYSentTestLog

+ (void)initialize
{
    [[NSUserDefaults standardUserDefaults] setValue:@"SPDYSentTestLog" forKey:SenTestObserverClassKey];

    [super initialize];
}

+ (void)testSuiteDidStop:(NSNotification *)notification
{
    [super testSuiteDidStop:notification];

    // workaround for missing flush with iOS 7 Simulator
    __gcov_flush();
}

@end

#endif