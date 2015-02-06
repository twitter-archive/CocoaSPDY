//
//  SPDYMockOriginEndpointTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import "SPDYMockOriginEndpointManager.h"

@interface SPDYOriginEndpointManager ()
- (void)_proxyExecuteAutoConfigURL:(NSURL *)pacScriptUrl;
- (void)_handleExecuteCallback:(NSArray *)proxies error:(NSError *)error;
@end

@implementation SPDYMockOriginEndpointManager

static void ResultCallback(void* client, CFArrayRef proxies, CFErrorRef error)
{
    SPDYMockOriginEndpointManager *manager = CFBridgingRelease(client);
    NSError *bridgedError = nil;
    NSArray *bridgedProxies = nil;
    if (error != NULL) {
        bridgedError = (__bridge NSError *)error;
    } else {
        bridgedProxies = (__bridge NSArray *)proxies;
    }
    [manager _handleExecuteCallback:bridgedProxies error:bridgedError];
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)_executeAutoConfigScript:(NSString *)script
{
    NSString *originUrlString = [NSString stringWithFormat:@"%@://%@:%u", [self origin].scheme, [self origin].host, [self origin].port];
    NSURL *originUrl = [NSURL URLWithString:originUrlString];

    CFStreamClientContext context = {0, (void *)CFBridgingRetain(self), nil, nil, nil};
    CFRunLoopSourceRef runLoopSource = CFNetworkExecuteProxyAutoConfigurationScript(
            (__bridge CFStringRef)script,
            (__bridge CFURLRef)originUrl,
            ResultCallback,
            &context);
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);
    CFRunLoopRun();
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);
    CFRelease(runLoopSource);
}

#pragma mark Overrides

- (NSDictionary *)_proxyGetSystemSettings
{
    // Don't need to hook this, will hook into next layer
    return nil;
}

- (NSArray *)_proxyGetListFromSettings:(NSDictionary *)systemProxySettings
{
    return _mock_proxyList;
}

- (void)_proxyExecuteAutoConfigURL:(NSURL *)pacScriptUrl
{
    if (_mock_autoConfigScript) {
        [self _executeAutoConfigScript:_mock_autoConfigScript];
    } else {
        [super _proxyExecuteAutoConfigURL:pacScriptUrl];
    }
}

@end
