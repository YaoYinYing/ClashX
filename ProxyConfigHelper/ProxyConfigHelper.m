//
//  ProxyConfigHelper.m
//  com.west2online.ClashX.ProxyConfigHelper
//
//  Created by yichengchen on 2019/8/17.
//  Copyright © 2019 west2online. All rights reserved.
//

#import "ProxyConfigHelper.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#include <arpa/inet.h>
#import "ProxyConfigRemoteProcessProtocol.h"
#import "ProxySettingTool.h"

@interface ProxyConfigHelper()
<
NSXPCListenerDelegate,
ProxyConfigRemoteProcessProtocol
>

@property (nonatomic, strong) NSXPCListener *listener;
@property (nonatomic, strong) NSMutableSet<NSXPCConnection *> *connections;
@property (nonatomic, strong) dispatch_queue_t connectionQueue;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) NSTimer *checkTimer;
@property (nonatomic, assign) BOOL shouldQuit;

@end

@implementation ProxyConfigHelper

static NSUInteger const kMaxIgnoreListEntries = 64;
static NSUInteger const kMaxIgnoreItemLength = 255;
static NSTimeInterval const kAutoQuitInterval = 30.0;
static NSTimeInterval const kRunLoopTick = 2.0;
static NSUInteger const kMaxConnections = 16;
static NSString * const kAllowedClientRequirementInfoKey = @"AllowedClientCodeSigningRequirement";
static NSString * const kHelperLogPrefix = @"[ProxyConfigHelper]";

- (instancetype)init {
    if (self = [super init]) {
        self.connections = [NSMutableSet new];
        self.shouldQuit = NO;
        self.connectionQueue = dispatch_queue_create("com.west2online.ClashX.ProxyConfigHelper.connections", DISPATCH_QUEUE_SERIAL);
        self.workQueue = dispatch_queue_create("com.west2online.ClashX.ProxyConfigHelper.work", DISPATCH_QUEUE_SERIAL);
        self.listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.west2online.ClashX.ProxyConfigHelper"];
        self.listener.delegate = self;
    }
    return self;
}

- (void)run {
    [self.listener resume];
    NSLog(@"%@ helper started pid=%d autoQuit=%gs maxConnections=%lu",
          kHelperLogPrefix, getpid(), kAutoQuitInterval, (unsigned long)kMaxConnections);
    self.checkTimer =
    [NSTimer timerWithTimeInterval:kAutoQuitInterval target:self selector:@selector(connectionCheckOnLaunch) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:self.checkTimer forMode:NSDefaultRunLoopMode];
    while (!self.shouldQuit) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:kRunLoopTick]];
    }
    NSLog(@"%@ helper exiting pid=%d", kHelperLogPrefix, getpid());
}

- (void)connectionCheckOnLaunch {
    __block NSUInteger count = 0;
    dispatch_sync(self.connectionQueue, ^{
        count = self.connections.count;
    });
    if (count == 0) {
        NSLog(@"%@ no connections after %gs, exiting", kHelperLogPrefix, kAutoQuitInterval);
        self.shouldQuit = YES;
    }
}

- (NSString *)allowedClientRequirement {
    NSString *requirement = [[NSBundle mainBundle] objectForInfoDictionaryKey:kAllowedClientRequirementInfoKey];
    if ([requirement isKindOfClass:[NSString class]]) {
        requirement = [requirement stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return requirement ?: @"";
}

- (BOOL)connectionIsValid:(NSXPCConnection *)connection {
    // Validate the calling process identity before accepting the XPC connection.
    // This privileged helper must only serve the signed SmartX/ClashX main app.
    pid_t pid = connection.processIdentifier;

    if (pid <= 0) {
        NSLog(@"%@ rejecting connection: invalid pid=%d", kHelperLogPrefix, pid);
        return NO;
    }

    NSRunningApplication *remoteApp =
    [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (remoteApp == nil) {
        NSLog(@"%@ rejecting connection: missing remote app for pid=%d", kHelperLogPrefix, pid);
        return NO;
    }

    NSString *requirement = [self allowedClientRequirement];
#if DEBUG
    if (requirement.length == 0) {
        // ponytail: verify bundle ID even when signing requirement is empty.
        // Prevents arbitrary local processes from connecting to the privileged
        // helper when installed via the legacy Debug path.
        NSString *bundleID = remoteApp.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.doodlenet.ClashX"]) {
            NSLog(@"%@ rejecting pid=%d in Debug: empty requirement but bundle ID '%@' does not match expected 'com.doodlenet.ClashX'",
                  kHelperLogPrefix, pid, bundleID ?: @"(nil)");
            return NO;
        }
        NSLog(@"%@ allowing pid=%d in Debug because %@ is empty and bundle ID matches",
              kHelperLogPrefix, pid, kAllowedClientRequirementInfoKey);
        return YES;
    }
#else
    if (requirement.length == 0) {
        NSLog(@"%@ rejecting pid=%d in Release because %@ is empty (fail-closed)", kHelperLogPrefix, pid, kAllowedClientRequirementInfoKey);
        return NO;
    }
#endif

    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid : @(pid)};
    SecCodeRef guestCode = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, kSecCSDefaultFlags, &guestCode);
    if (status != errSecSuccess || guestCode == NULL) {
        NSLog(@"%@ rejecting pid=%d: SecCodeCopyGuestWithAttributes failed status=%d", kHelperLogPrefix, pid, (int)status);
        return NO;
    }
    SecRequirementRef secRequirement = NULL;
    status = SecRequirementCreateWithString((__bridge CFStringRef)requirement, kSecCSDefaultFlags, &secRequirement);
    if (status != errSecSuccess || secRequirement == NULL) {
        NSLog(@"%@ rejecting pid=%d: invalid signing requirement status=%d", kHelperLogPrefix, pid, (int)status);
        if (guestCode != NULL) { CFRelease(guestCode); }
        return NO;
    }
    status = SecCodeCheckValidity(guestCode, kSecCSDefaultFlags, secRequirement);
    CFRelease(secRequirement);
    CFRelease(guestCode);
    if (status != errSecSuccess) {
        NSLog(@"%@ rejecting pid=%d: SecCodeCheckValidity failed status=%d", kHelperLogPrefix, pid, (int)status);
    }
    return status == errSecSuccess;
}

- (BOOL)portIsValid:(int)port {
    return port >= 1 && port <= 65535;
}

- (BOOL)isValidPacURL:(NSString *)pac {
    if (pac == nil || pac.length == 0) {
        return YES;
    }
    // PAC URL is written into system proxy preferences by a privileged helper.
    // Restrict it to local loopback HTTP(S) endpoints controlled by the app.
    NSURL *url = [NSURL URLWithString:pac];
    if (url == nil || url.scheme == nil) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return NO;
    }
    NSString *host = url.host.lowercaseString ?: @"";
    if ([host isEqualToString:@"localhost"]) {
        return YES;
    }
    if ([host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"::1"]) {
        return YES;
    }
    struct in_addr ipv4Addr;
    if (inet_pton(AF_INET, host.UTF8String, &ipv4Addr) == 1) {
        if ((ntohl(ipv4Addr.s_addr) >> 24) == 127) {
            return YES;
        }
        return NO;
    }
    struct in6_addr ipv6Addr;
    if (inet_pton(AF_INET6, host.UTF8String, &ipv6Addr) == 1 && IN6_IS_ADDR_LOOPBACK(&ipv6Addr)) {
        return YES;
    }
    return NO;
}

- (BOOL)isValidIgnoreList:(NSArray<NSString *> *)ignoreList {
    if (ignoreList == nil) {
        return NO;
    }
    if (![ignoreList isKindOfClass:[NSArray class]] || ignoreList.count > kMaxIgnoreListEntries) {
        return NO;
    }
    NSCharacterSet *invalidSet = [NSCharacterSet characterSetWithCharactersInString:@"\n\r\t"];
    for (NSString *item in ignoreList) {
        if (![item isKindOfClass:[NSString class]] || item.length == 0 || item.length > kMaxIgnoreItemLength) {
            return NO;
        }
        if ([item rangeOfCharacterFromSet:invalidSet].location != NSNotFound) {
            return NO;
        }
    }
    return YES;
}

// MARK: - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    // Trust boundary: this helper is privileged and must only serve the signed main app.
    // It only manages system proxy preferences and must not be expanded to general operations.

    if (![self connectionIsValid:newConnection]) {
        NSLog(@"%@ rejected XPC connection for pid=%d", kHelperLogPrefix, newConnection.processIdentifier);
        return NO;
    }

    // ponytail: atomically check limit + reserve slot to avoid TOCTOU race
    __block BOOL shouldAccept = NO;
    dispatch_sync(self.connectionQueue, ^{
        if (self.connections.count >= kMaxConnections) {
            NSLog(@"%@ rejecting connection from pid=%d: connection limit %lu reached",
                  kHelperLogPrefix, newConnection.processIdentifier, (unsigned long)kMaxConnections);
            return;
        }
        shouldAccept = YES;
        [self.connections addObject:newConnection];
    });

    if (!shouldAccept) {
        return NO;
    }

    NSLog(@"%@ accepted XPC connection for pid=%d", kHelperLogPrefix, newConnection.processIdentifier);

    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ProxyConfigRemoteProcessProtocol)];
    newConnection.exportedObject = self;

    __weak NSXPCConnection *weakConnection = newConnection;
    __weak ProxyConfigHelper *weakSelf = self;
    pid_t pid = newConnection.processIdentifier;

    newConnection.invalidationHandler = ^{
        NSLog(@"%@ connection invalidated for pid=%d", kHelperLogPrefix, pid);
        dispatch_async(weakSelf.connectionQueue, ^{
            [weakSelf.connections removeObject:weakConnection];
            // ponytail: already on connectionQueue — no nested dispatch needed
            if (weakSelf.connections.count == 0) {
                weakSelf.shouldQuit = YES;
            }
        });
    };

    if ([newConnection respondsToSelector:@selector(setInterruptionHandler:)]) {
        newConnection.interruptionHandler = ^{
            NSLog(@"%@ connection interrupted for pid=%d", kHelperLogPrefix, pid);
        };
    }

    [newConnection resume];
    return YES;
}

// MARK: - ProxyConfigRemoteProcessProtocol

- (void)getVersion:(stringReplyBlock)reply {
    if (reply == nil) {
        return;
    }
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (version == nil) {
        version = @"unknown";
    }
    reply(version);
}

- (void)enableProxyWithPort:(int)port
          socksPort:(int)socksPort
                pac:(NSString *)pac
    filterInterface:(BOOL)filterInterface
         ignoreList:(NSArray<NSString *>*)ignoreList
              error:(stringReplyBlock)reply {
    if (reply == nil) {
        return;
    }
    if (![self portIsValid:port]) {
        reply(@"EINVAL: Invalid HTTP proxy port");
        NSLog(@"%@ enableProxy rejected: invalid port=%d", kHelperLogPrefix, port);
        return;
    }
    if (![self portIsValid:socksPort]) {
        reply(@"EINVAL: Invalid SOCKS proxy port");
        NSLog(@"%@ enableProxy rejected: invalid socksPort=%d", kHelperLogPrefix, socksPort);
        return;
    }
    if (![self isValidPacURL:pac]) {
        reply(@"EINVAL: Invalid PAC URL");
        NSLog(@"%@ enableProxy rejected: invalid PAC URL", kHelperLogPrefix);
        return;
    }
    if (![self isValidIgnoreList:ignoreList]) {
        reply(@"EINVAL: Invalid ignore list");
        NSLog(@"%@ enableProxy rejected: invalid ignore list", kHelperLogPrefix);
        return;
    }

    dispatch_async(self.workQueue, ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool enableProxyWithport:port socksPort:socksPort pacUrl:pac filterInterface:filterInterface ignoreList:ignoreList];
        NSLog(@"%@ enableProxy HTTP=%d SOCKS=%d", kHelperLogPrefix, port, socksPort);
        reply(nil);
    });
}

- (void)disableProxyWithFilterInterface:(BOOL)filterInterface reply:(stringReplyBlock)reply {
    if (reply == nil) {
        return;
    }
    dispatch_async(self.workQueue, ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool disableProxyWithfilterInterface:filterInterface];
        NSLog(@"%@ disableProxy", kHelperLogPrefix);
        reply(nil);
    });
}


- (void)restoreProxyWithCurrentPort:(int)port
                          socksPort:(int)socksPort
                               info:(NSDictionary *)dict
                    filterInterface:(BOOL)filterInterface
                              error:(stringReplyBlock)reply {
    if (reply == nil) {
        return;
    }
    if (![self portIsValid:port]) {
        reply(@"EINVAL: Invalid proxy port");
        return;
    }
    if (![self portIsValid:socksPort]) {
        reply(@"EINVAL: Invalid SOCKS proxy port");
        return;
    }
    if (![dict isKindOfClass:[NSDictionary class]]) {
        reply(@"EINVAL: Invalid restore payload — dictionary required");
        return;
    }

    dispatch_async(self.workQueue, ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool restoreProxySetting:dict currentPort:port currentSocksPort:socksPort filterInterface:filterInterface];
        NSLog(@"%@ restoreProxy", kHelperLogPrefix);
        reply(nil);
    });
}

- (void)getCurrentProxySetting:(dictReplyBlock)reply {
    if (reply == nil) {
        return;
    }
    dispatch_async(self.workQueue, ^{
        NSDictionary *info = [ProxySettingTool currentProxySettings];
        reply(info);
    });
}


@end
