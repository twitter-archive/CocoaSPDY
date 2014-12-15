//
//  SPDYOriginEndpointTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYMockOriginEndpointManager.h"
#import "SPDYOriginEndpoint.h"
#import "SPDYProtocol.h"

@interface SPDYOriginEndpointTest : SenTestCase
@end

@implementation SPDYOriginEndpointTest

- (void)testOriginEndpointInit
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYOriginEndpoint *endpoint = [[SPDYOriginEndpoint alloc] initWithHost:@"1.2.3.4"
                                                                      port:8888
                                                                      user:@"user"
                                                                  password:@"pass"
                                                                      type:SPDYOriginEndpointTypeHttpsProxy
                                                                    origin:origin];
    NSLog(@"%@", endpoint); // ensure description doesn't crash
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", nil);
    STAssertEquals(endpoint.port, (in_port_t)8888, nil);
    STAssertEqualObjects(endpoint.user, @"user", nil);
    STAssertEqualObjects(endpoint.password, @"pass", nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(endpoint.origin, origin, nil);
}

- (void)testOriginManagerInit
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    STAssertNil(error, nil);

    SPDYOriginEndpointManager *manager = [[SPDYOriginEndpointManager alloc] initWithOrigin:origin];
    STAssertEqualObjects(manager.origin, origin, nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertNil([manager selectNextEndpoint], nil);

    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertNil([manager selectNextEndpoint], nil);
}

- (void)testOriginManagerResolveWithNoProxyConfig
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
        STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    }];

    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
}

- (void)testOriginManagerResolveWithDirectProxyConfig
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeNone,
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager selectNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
    STAssertEqualObjects(endpoint.host, @"mytesthost.com", nil);
    STAssertEquals(endpoint.port, (in_port_t)443, nil);
    STAssertEqualObjects(endpoint.origin, origin, nil);
    STAssertNil(endpoint.user, nil);
    STAssertNil(endpoint.password, nil);
}

- (void)testOriginManagerResolveWithHttpsProxyConfig
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager selectNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", nil);
    STAssertEquals(endpoint.port, (in_port_t)8888, nil);
    STAssertEqualObjects(endpoint.origin, origin, nil);
    STAssertNil(endpoint.user, @"actual: %@", nil);
    STAssertNil(endpoint.password, @"actual: %@", nil);
}

- (void)testOriginManagerResolveWithHttpsAndDirectProxyConfigShouldReturnSingleProxy
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }, @{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeNone,
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    // Note: currently only support a single proxy.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    // The first config in the array gets used, so verify that.
    SPDYOriginEndpoint *endpoint = [manager selectNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", nil);
    STAssertEquals(endpoint.port, (in_port_t)8888, nil);
}

- (void)testOriginManagerResolveWithEmptyAutoConfigURLShouldReturnError
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    // This URL will clearly result in an error, but will go through the Apple API to execute it.
    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeAutoConfigurationURL,
            (__bridge NSString *)kCFProxyAutoConfigurationURLKey : @""
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
        CFRunLoopStop(CFRunLoopGetCurrent());
    }];

    // The callback will happen asynchronously on the current runloop.
    CFRunLoopRun();

    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
}

- (void)testOriginManagerResolveWithPacScriptIsNotSupported
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeAutoConfigurationJavaScript
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
}

- (void)testOriginManagerResolveWithHttpsProxyConfigWhenDisabledReturnsDirect
{
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.enableProxy = NO;
    [SPDYProtocol setConfiguration:configuration];

    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager selectNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
    STAssertEqualObjects(endpoint.host, @"mytesthost.com", nil);
    STAssertEquals(endpoint.port, (in_port_t)443, nil);
    STAssertEqualObjects(endpoint.origin, origin, nil);

    // Remember to reset global config!
    [SPDYProtocol setConfiguration:[SPDYConfiguration defaultConfiguration]];
}

- (void)testOriginManagerResolveWithConfigOverrides
{
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.proxyHost = @"proxyproxyproxy.com";
    configuration.proxyPort = 9999;
    [SPDYProtocol setConfiguration:configuration];

    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    STAssertTrue(gotCallback, nil);

    SPDYOriginEndpoint *endpoint = [manager selectNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(endpoint.host, @"proxyproxyproxy.com", nil);
    STAssertEquals(endpoint.port, (in_port_t)9999, nil);
    STAssertEqualObjects(endpoint.origin, origin, nil);

    // Remember to reset global config!
    [SPDYProtocol setConfiguration:[SPDYConfiguration defaultConfiguration]];
}

@end
