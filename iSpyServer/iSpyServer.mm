/*
 * iSpy - Bishop Fox iOS hacking/hooking/sandboxing framework.
 */

#include <stack>
#include <fcntl.h>
#include <stdio.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>
#include <stdbool.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <objc/objc.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <mach-o/dyld.h>
#include <netinet/in.h>
#import  <Security/Security.h>
#import  <Security/SecCertificate.h>
#include <CFNetwork/CFNetwork.h>
#include <CFNetwork/CFProxySupport.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFStream.h>
#import  <Foundation/NSJSONSerialization.h>
#include <dlfcn.h>
#include <mach-o/nlist.h>
#include <semaphore.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "CocoaHTTPServer/Vendor/CocoaLumberjack/DDLog.h"
#import "CocoaHTTPServer/Vendor/CocoaLumberjack/DDTTYLogger.h"
#import "iSpyHTTPServer.h"
#import "iSpyHTTPConnection.h"
#include "../iSpy.common.h"
#include "../iSpy.instance.h"
#include "../iSpy.class.h"
#import "RPCHandler.h"
#import "SSZipArchive.h"


static const int MAX_ATTEMPTS = 5;
static const int DEFAULT_WEB_PORT = 31337;
static const char *WS_QUEUE = "com.bishopfox.iSpy.websocket";
static dispatch_queue_t wsQueue = dispatch_queue_create(WS_QUEUE, NULL);

extern const unsigned char *webrootZIPData;
extern unsigned int WEBROOT_SIZE;

//#define DEBUG(...) NSLog(__VA_ARGS__)
#define DEBUG(...) {}

@implementation iSpyServer

-(void)configureWebServer {

    int attempts = 0;
    BOOL successful = NO;
    int settingsPort = DEFAULT_WEB_PORT; //[self getListenPortFor:@"settings_webServerPort" fallbackTo:DEFAULT_WEB_PORT];
    int lport = settingsPort;
    iSpy *mySpy = [iSpy sharedInstance];

    // First we extract the webroot from the dylib
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSString *zipPath = [NSString stringWithFormat:@"%@/ispy/webroot.zip", [mySpy docPath]];
    NSString *webrootPath = [NSString stringWithFormat:@"%@/ispy/www", [mySpy docPath]];
    [fm createDirectoryAtPath:webrootPath withIntermediateDirectories:true attributes:nil error:nil];

    FILE *fp = fopen([zipPath UTF8String], "w");
    if(!fp) {
        NSLog(@"[iSpy configureWebServer] WTF - couldn't create ZIP file");
        return;
    }
    fwrite(webrootZIPData, 1, WEBROOT_SIZE, fp);
    fclose(fp);

    // Extract the data
    NSLog(@"[iSpy configureWebServer] Extracting ZIP file to %@", webrootPath);
    [SSZipArchive unzipFileAtPath:zipPath toDestination:webrootPath];

    do
    {
        //[self setPlist:NULL];
        //[self setPlist: [[NSMutableDictionary alloc] initWithContentsOfFile:@PREFERENCEFILE]];

        [self setHttpServer:NULL];
        NSLog(@"[iSpy] Start iSpyHTTPServer, attempt #%d ...", attempts + 1);

        iSpyHTTPServer *httpServer = [[iSpyHTTPServer alloc] init];
        [self setHttpServer:httpServer];

        // Tell server to use our custom MyHTTPConnection class.
        [httpServer setConnectionClass:[iSpyHTTPConnection class]];
        [httpServer setPort: lport];
        NSLog(@"[iSpy] iSpyHTTPServer attempting to listen on port %d", lport);

        [httpServer setDocumentRoot: [NSString stringWithFormat:@"%@/ispy/www/iSpyServer/HTML",[[iSpy sharedInstance] docPath]]];

        // Serve files from our embedded Web folder
        NSLog(@"[iSpy] DocumentRoot: %@", [httpServer documentRoot]);

        NSError *error;
        if ([httpServer start:&error])
        {
            successful = YES;
        }
        else
        {
            NSString *errorMessage = [NSString stringWithFormat:@"%@", error];
            NSLog(@"[iSpy] Error starting HTTP Server: %@", errorMessage);
            ++lport;
            ++attempts;
        }
    } while ( ! successful && attempts < MAX_ATTEMPTS);

    if (successful)
    {
        NSLog(@"[iSpy] HTTP server started successfully on port %d", lport);
    }
    else
    {
        NSLog(@"[iSpy] Failed to start web server, max attempts");
    }

}

/*
-(id)init {
    [super init];
    NSLog(@"INIT - YOYOYOYOYOYOYOYOYO");
    return self;
}*/

-(void)bounceWebServer {
    ispy_log("bounceWebServer...");
}

/* not called at this time.
-(int) getListenPortFor:(NSString *) key fallbackTo:(int) fallback
{
    int lport = [[self.plist objectForKey:key] intValue];
    if (lport <= 0 || 65535 <= lport)
    {
        NSLog(@"[iSpy] Invalid listen port (%d); fallback to %d", lport, fallback);
        lport = fallback;
    }
    if (lport <= 1024)
    {
        NSLog(@"[iSpy] %d is a priviledged port, this is most likely not going to work!", lport);
    }
    return lport;
}
*/

-(NSDictionary *)dispatchRPCRequest:(NSString *) JSONString {
    NSLog(@"Dispatching RPC request: %@", JSONString);

    NSData *RPCRequest = [JSONString dataUsingEncoding:NSUTF8StringEncoding];
    if ( ! RPCRequest)
    {
        ispy_log("Could not convert websocket payload into NSData");
        return nil;
    }

    // create a dictionary from the JSON request
    NSDictionary *RPCDictionary = [NSJSONSerialization JSONObjectWithData:RPCRequest options:kNilOptions error:nil];
    if ( ! RPCDictionary)
    {
        ispy_log("invalid RPC request, couldn't deserialze the JSON data.");
        return nil;
    }

    // is this a valid request? (does it contain both "messageType" and "messageData" entries?)
    if ( ! [RPCDictionary objectForKey:@"messageType"] || ! [RPCDictionary objectForKey:@"messageData"])
    {
        ispy_log("Invalid RPC request; must have messageType and messageData.");
        return nil;
    }

    // Verify that the iSpy RPC handler class can execute the requested selector
    NSString *selectorString = [RPCDictionary objectForKey:@"messageType"];
    SEL selectorName = sel_registerName([[NSString stringWithFormat:@"%@:", selectorString] UTF8String]);
    if ( ! selectorName)
    {
        ispy_log("selectorName was null.");
        return nil;
    }
    if ( ! [[self RPCHandler] respondsToSelector:selectorName] )
    {
        ispy_log("doesn't respond to selector");
        return nil;
    }

    // Do it!
    ispy_log("Dispatching request for: %s", [selectorString UTF8String]);
    NSDictionary *responseDict = [[self RPCHandler] performSelector:selectorName withObject:[RPCDictionary objectForKey:@"messageData"]];
    NSMutableDictionary *mutableResponse = [responseDict mutableCopy];
    [mutableResponse setObject:selectorString forKey:@"messageType"];
    ispy_log("Created valid response for %s", [selectorString UTF8String]);
    return mutableResponse;
}

@end

