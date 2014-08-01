# CocoaSPDY
#### A SPDY/3.1 framework for iOS and Mac OS X

[![Build Status](https://travis-ci.org/twitter/CocoaSPDY.png?branch=master)](https://travis-ci.org/twitter/CocoaSPDY)

### [Download v1.0.2](https://github.com/twitter/CocoaSPDY/releases/download/v1.0.2/SPDY.framework.tar.gz)

## The SPDY protocol
The short version is that [SPDY](http://en.wikipedia.org/wiki/SPDY) can make your HTTP requests faster. Sometimes a lot faster. For more details, see the following:

http://www.chromium.org/spdy/spdy-whitepaper  
http://www.chromium.org/spdy/spdy-protocol/spdy-protocol-draft3-1

SPDY was originally designed at Google as an experimental successor to HTTP. It's a binary protocol (rather than human-readable, like HTTP), but is fully compatible with HTTP. In fact, current draft work on [HTTP/2.0](https://github.com/http2/http2-spec) is largely based on the SPDY protocol and its real-world success.

In order to make HTTP requests go faster SPDY makes several improvements:

The first, and arguably most important, is request multiplexing. Rather than sending one request at a time over one TCP connection, SPDY can issue many requests simultaneously over a single TCP session and handle responses in any order, as soon as they're available.

Second, SPDY compresses both request and response headers. Headers are often nearly identical to each other across requests, generally contain lots of duplicated text, and can be quite large. This makes them an ideal candidate for compression.<sup>1</sup>

Finally, SPDY introduces server push.<sup>2</sup> This can allow a server to push content that the client doesn't know it needs yet. Such content can range from additional assets like styles and images, to notifications about realtime events.

1. Please see the note below about the CRIME attack.  
2. Not currently supported in this framework, but coming soon.

## Getting Started
The SPDY framework is designed to work seamlessly with your existing apps and projects. If you are using the NSURL stack to issue requests (or any library that provides an abstraction over it, like AFNetworking), you can simply add the SPDY framework bundle to your project, link it to your targets, and enable the protocol.

The framework contains a multi-architecture/multi-platform ("fat") binary that supports versions of iOS 6 and above, and OS X Lion and above, as well as all hardware capable of running those operating systems. When you distribute your application, the size of the included binary will be dramatically reduced, provided you have code stripping enabled.

## Enabling SPDY

To use the SPDY framework you'll need to link CFNetwork.framework and libz.dylib in your project. This can be done in the "Link Binary with Libraries" section under "Build Phases" for your compilation target.

The way you enable SPDY in your application will be slightly different depending on whether you are using NSURLConnection or NSURLSession to manage your HTTP calls. In order to cause requests issued via the NSURLConnection stack to be carried over SPDY, you'll make a method call to specify one or more origins (protocol-host-port tuple) to be handled by SPDY:

    #import <SPDY/SPDYProtocol.h>
    ...
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com:443"];

Note that origins containing "http" vs. "https" are distinct from each other, will be handled by separate SPDY sessions, and must be registered independently. Only sessions for origins containing "https" will be encrypted with TLS.

For NSURLSession, you can configure sessions to use SPDY via NSURLSessionConfiguration:

    #import <SPDY/SPDYProtocol.h>
    ...
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.protocolClasses = @[[SPDYURLSessionProtocol class]];

You can freely use either or both methods, and existing SPDY sessions will be shared across both networking stacks. If you do use the former approach, note that registered origins will also be handled by SPDY with the default NSURLSession.

Either of the above one-liners is all you need to do to shift HTTP requests transparently over to SPDY. Of course you still need a server that speaks SPDY! Some possibilities are:

* [netty](http://netty.io/4.0/api/io/netty/handler/codec/spdy/package-summary.html)
* [jetty](http://www.eclipse.org/jetty/documentation/current/spdy.html)
* apache (with [mod_spdy](https://code.google.com/p/mod-spdy/))
* [nginx](http://nginx.org/)
* [Tengine](https://github.com/alibaba/tengine)

## A note on NPN
Most existing SPDY implementations use a TLS extension called Next Protocol Implementation (NPN) to negotiate SPDY instead of HTTP. Unfortunately, this extension isn't supported by Secure Transport (Apple's TLS implementation), and so in order to use SPDY in your application, you'll either need to issue requests to a server that's configured to speak SPDY on a dedicated port, or use a server that's smart enough to examine the incoming request and determine whether the connection will be SPDY or HTTP based on what it looks like. At Twitter we do the latter, but the former solution may be simpler for most applications.

In order to aid with protocol inference, this SPDY implementation includes a non-standard settings id at index 0: `SETTINGS_MINOR_VERSION`. This is necessary to differentiate between SPDY/3 and SPDY/3.1 connections that were not negotiated with NPN, since only the major version is included in the frame header. Because not all servers may support this particular setting, sending it can be disabled at runtime through protocol configuration.

## Implementation Notes
### CRIME attack
The [CRIME attack](http://en.wikipedia.org/wiki/CRIME) is a plaintext injection technique that exploits the fact that information can be inferred from compressed content length to potentially reveal the contents of an encrypted stream. This is a serious issue for browsers, which are subject to hijacks that may allow an attacker to issue an arbitrary number of requests with known plaintext header content and observe the resulting effect on compression. 

In the context of an application that doesn't issue arbitrary requests, this is less likely to be an issue. However, before you ship a project with header compression enabled, you should understand the details of this attack and whether your application could be vulnerable.

## Building the Framework Yourself
If you wish to compile the framework yourself, the process is fairly straightforward, and the build process should just work out of the box in Xcode. However, there are still a couple of things to note.

Prior to Xcode 5, if you wanted to compile the framework to a dual-platform binary (as in the distribution version), you were required to set 'iOS Device' as your platform target for the framework. This was due to a quirk in the Xcode build process that would otherwise exclude some (but not all) versions of the ARM architecture from the final binary. With the release of Xcode 5, any platform target should result in the same final universal binary (the setting is essentially ignored).

To create this binary, the build process actually depends on several static library targets and uses lipo to combine them.

## Getting involved and Future work
We are always looking for people to get involved with the project.

In the near future, we will be working on:

* [Server Push](https://github.com/twitter/CocoaSPDY/issues/1)
* [Discretionary/Deferrable Request Scheduling](https://github.com/twitter/CocoaSPDY/issues/2)

## Adopters

* [Amahi](https://github.com/twitter/CocoaSPDY/issues/9#issuecomment-31307581)
* [Twitter](https://twitter.com/TwitterOSS/status/413746448367230976)

Please feel free to send us a pull request to add yourself to this list (bonus points to link to a tweet).

## Problems?
If you find any issues please [report them](https://github.com/twitter/CocoaSPDY/issues) or better,
send a [pull request](https://github.com/twitter/CocoaSPDY/pulls).

## Authors
* Michael Schore <https://twitter.com/goaway>
* Jeffrey Pinner <https://twitter.com/jpinner>

## License
Copyright 2014 Twitter, Inc. and other contributors.

Licensed under the Apache License, Version 2.0: http://www.apache.org/licenses/LICENSE-2.0
