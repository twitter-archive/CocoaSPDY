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
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", @"actual: %@", endpoint.host);
    STAssertEquals(endpoint.port, (in_port_t)8888, @"actual: %@", endpoint.port);
    STAssertEqualObjects(endpoint.user, @"user", @"actual: %@", endpoint.user);
    STAssertEqualObjects(endpoint.password, @"pass", @"actual: %@", endpoint.password);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, @"actual: %@", endpoint.type);
    STAssertEqualObjects(endpoint.origin, origin, @"actual: %@", endpoint.origin);
}

- (void)testOriginManagerInit
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    STAssertNil(error, nil);

    SPDYOriginEndpointManager *manager = [[SPDYOriginEndpointManager alloc] initWithOrigin:origin];
    STAssertEqualObjects(manager.origin, origin, nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertNil([manager getCurrentEndpoint], nil);

    STAssertFalse([manager moveToNextEndpoint], nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertNil([manager getCurrentEndpoint], nil);
}

- (void)testOriginManagerResolveWithNoProxyConfig
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    [manager resolveEndpointsAndThen:^{
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

    [manager resolveEndpointsAndThen:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    STAssertTrue([manager moveToNextEndpoint], nil);

    SPDYOriginEndpoint *endpoint = [manager getCurrentEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, @"actual: %@", endpoint.type);
    STAssertEqualObjects(endpoint.host, @"mytesthost.com", @"actual: %@", endpoint.host);
    STAssertEquals(endpoint.port, (in_port_t)443, @"actual: %@", endpoint.port);
    STAssertEqualObjects(endpoint.origin, origin, @"actual: %@", endpoint.origin);
    STAssertNil(endpoint.user, @"actual: %@", endpoint.user);
    STAssertNil(endpoint.password, @"actual: %@", endpoint.password);
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

    [manager resolveEndpointsAndThen:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    STAssertTrue([manager moveToNextEndpoint], nil);

    SPDYOriginEndpoint *endpoint = [manager getCurrentEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, @"actual: %@", endpoint.type);
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", @"actual: %@", endpoint.host);
    STAssertEquals(endpoint.port, (in_port_t)8888, @"actual: %@", endpoint.port);
    STAssertEqualObjects(endpoint.origin, origin, @"actual: %@", endpoint.origin);
    STAssertNil(endpoint.user, @"actual: %@", endpoint.user);
    STAssertNil(endpoint.password, @"actual: %@", endpoint.password);
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

    [manager resolveEndpointsAndThen:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    // Note: currently only support a single proxy.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    STAssertTrue([manager moveToNextEndpoint], nil);

    // The first config in the array gets used, so verify that.
    SPDYOriginEndpoint *endpoint = [manager getCurrentEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, @"actual: %@", endpoint.type);
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", @"actual: %@", endpoint.host);
    STAssertEquals(endpoint.port, (in_port_t)8888, @"actual: %@", endpoint.port);
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

    [manager resolveEndpointsAndThen:^{
        gotCallback = YES;
        CFRunLoopStop(CFRunLoopGetCurrent());
    }];

    // The callback will happen asynchronously on the current runloop.
    CFRunLoopRun();

    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertFalse([manager moveToNextEndpoint], nil);
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

    [manager resolveEndpointsAndThen:^{
        gotCallback = YES;
    }];

    // Callbacks happens synchronously with no auto-config URL.
    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertFalse([manager moveToNextEndpoint], nil);
}

@end
