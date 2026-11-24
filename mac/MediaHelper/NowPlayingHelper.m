// Now Playing helper for NotchBridge.
//
// Since macOS 15.4, mediaremoted only answers processes with Apple's MediaRemote entitlement.
// /usr/bin/perl has it, so NotchBridge runs:
//
//   /usr/bin/perl -e '<loader>' libNowPlayingHelper.dylib nb_stream     # JSON line per change on stdout
//   NB_MEDIA_CMD=<n> /usr/bin/perl -e '<loader>' libNowPlayingHelper.dylib nb_send
//
// where <loader> uses DynaLoader to load this library and call the symbol as an XSUB.
// (Same technique as github.com/ungive/mediaremote-adapter; this is an independent, minimal version.)
// MediaRemote is a private framework: everything is looked up with dlsym and may break in future macOS.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef void (*MRIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*MRClientStringFn)(id);
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);

static void *mr;
static NSUInteger lastArtSignature;
static BOOL emitScheduled;

static void loadMediaRemote(void) {
    if (!mr) mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) {
        fprintf(stdout, "{\"error\":\"MediaRemote not found\"}\n");
        fflush(stdout);
        exit(2);
    }
}

static void writeJSON(NSDictionary *obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void emitNow(void) {
    MRGetInfoFn getInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    MRIsPlayingFn isPlaying = (MRIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MRGetClientFn getClient = (MRGetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    MRClientStringFn bundleOf = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    MRClientStringFn parentOf = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    if (!getInfo || !isPlaying) return;

    dispatch_queue_t q = dispatch_get_main_queue();
    getInfo(q, ^(NSDictionary *info) {
        isPlaying(q, ^(Boolean playing) {
            void (^finish)(id) = ^(id client) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"playing"] = @(playing);
                if (info.count == 0) {
                    out[@"empty"] = @YES;
                    writeJSON(out);
                    return;
                }
                NSDictionary *keys = @{
                    @"title": @"kMRMediaRemoteNowPlayingInfoTitle",
                    @"artist": @"kMRMediaRemoteNowPlayingInfoArtist",
                    @"album": @"kMRMediaRemoteNowPlayingInfoAlbum",
                    @"duration": @"kMRMediaRemoteNowPlayingInfoDuration",
                    @"elapsed": @"kMRMediaRemoteNowPlayingInfoElapsedTime",
                    @"rate": @"kMRMediaRemoteNowPlayingInfoPlaybackRate",
                };
                for (NSString *k in keys) {
                    id v = info[keys[k]];
                    if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]) out[k] = v;
                }
                id ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if ([ts isKindOfClass:[NSDate class]]) out[@"timestamp"] = @([(NSDate *)ts timeIntervalSince1970]);

                if (client) {
                    NSString *parent = parentOf ? parentOf(client) : nil;
                    NSString *bundle = bundleOf ? bundleOf(client) : nil;
                    if (parent.length) out[@"bundle"] = parent;
                    else if (bundle.length) out[@"bundle"] = bundle;
                }

                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([art isKindOfClass:[NSData class]] && art.length > 0) {
                    NSUInteger sig = art.hash ^ (art.length << 7);
                    out[@"artId"] = @(sig);
                    if (sig != lastArtSignature) {
                        out[@"art"] = [art base64EncodedStringWithOptions:0];
                        lastArtSignature = sig;
                    }
                }
                writeJSON(out);
            };
            if (getClient) getClient(q, finish); else finish(nil);
        });
    });
}

/// Coalesce bursts of notifications into one update.
static void scheduleEmit(void) {
    if (emitScheduled) return;
    emitScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        emitScheduled = NO;
        emitNow();
    });
}

/// XSUB entry: stream now-playing changes forever (until stdin closes, i.e. NotchBridge quit).
void nb_stream(void *interp, void *cv) {
    @autoreleasepool {
        loadMediaRemote();
        MRRegisterFn reg = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (reg) reg(dispatch_get_main_queue());

        for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange"]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                          usingBlock:^(NSNotification *n) { scheduleEmit(); }];
        }

        // Exit when our parent goes away (its end of the stdin pipe closes).
        dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(src, ^{
            char buf[256];
            if (read(STDIN_FILENO, buf, sizeof buf) <= 0) exit(0);
        });
        dispatch_resume(src);

        emitNow();
        CFRunLoopRun();
    }
    exit(0);
}

/// XSUB entry: send one MRMediaRemoteSendCommand (number in $NB_MEDIA_CMD) and exit.
/// 0 play, 1 pause, 2 toggle play/pause, 4 next track, 5 previous track.
void nb_send(void *interp, void *cv) {
    @autoreleasepool {
        loadMediaRemote();
        MRSendCommandFn send = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        const char *c = getenv("NB_MEDIA_CMD");
        Boolean ok = (send && c) ? send(atoi(c), nil) : false;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
        exit(ok ? 0 : 1);
    }
}
