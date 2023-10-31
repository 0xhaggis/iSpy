#include <ifaddrs.h>
#include <arpa/inet.h>
#import <Foundation/Foundation.h>

#import "CocoaHTTPServer/Core/HTTPConnection.h"
#import "CocoaHTTPServer/Core/Responses/HTTPDataResponse.h"
#import "iSpyStaticFileResponse.h"
#import "iSpyWebSocket.h"
//#import "CycriptWebSocket.h"
#import "../iSpy.common.h"
#import "../iSpy.class.h"
#import "iSpyHTTPConnection.h"

//#define DEBUG(...) NSLog(__VA_ARGS__)
#define DEBUG(...) {}

@implementation iSpyHTTPConnection

- (BOOL)supportsMethod:(NSString *)method atPath:(NSString *)path
{
    DEBUG(@"[supportsMethod]");

    // Add support for POST
    if ([method isEqualToString:@"POST"])
        if ([path isEqualToString:@"/rpc"])
            return true;

    // Support for IPA download
    if([method isEqualToString:@"GET"])
        if([path isEqualToString:@"/ipa"])
            return true;

    return [super supportsMethod:method atPath:path];
}

- (BOOL)expectsRequestBodyFromMethod:(NSString *)method atPath:(NSString *)path
{
    DEBUG(@"[expectsRequestBodyFromMethod]");
    if(!method || !path)
        return false;

    if([method isEqualToString:@"POST"])
       return YES;
    return [super expectsRequestBodyFromMethod:method atPath:path];
}

// REQUIRED in order to process POST requests
- (void)processBodyData:(NSData *)postDataChunk
{
    if(!postDataChunk)
        return;
    
    [request appendData:postDataChunk];
}

/*
 * This is almost identical to the parent objects impl but we use an
 * iSpyStaticFileResponse object instead of an HTTPFileResponse object.
 */
-(iSpyStaticFileResponse *) httpResponseForMethod:(NSString *)method URI:(NSString *)path
{
    DEBUG(@"[httpResponseForMethod]");
    if(!method || !path)
        return nil;
    
    // Handle JSON RPC requests via HTTP POST. Also support websockets on /jsonrpc/
    if([path isEqualToString:@"/rpc"] && [method isEqualToString:@"POST"])
    {
        NSError *error;

        // Convert the POST request body into an NSString
        NSString *body = [[NSString alloc] initWithData:[request body] encoding:NSUTF8StringEncoding];

        // Dispatch the RPC request
        NSDictionary *responseDict = [[[iSpy sharedInstance] webServer] dispatchRPCRequest:body];

        if(responseDict == nil)
            responseDict = (NSDictionary *)@{};
        //DEBUG(@"httpResponseForMethod: Received object: %@", responseDict);

        // Convert the response to NSData
        @try {
            NSData *responseData = [NSJSONSerialization dataWithJSONObject:responseDict options:0 error:&error];    
            //DEBUG(@"httpResponseForMethod: Received data: %@"  , responseData);
            // Return the result to the caller as a JSON blob
            return (iSpyStaticFileResponse *)[[HTTPDataResponse alloc] initWithData:responseData];
        } @catch (NSException *e) {
            DEBUG(@"FAILED: %@", e);
        }
        
        return nil;
    }

    // Return the decrypted .ipa when asked
    BOOL isDir = NO;
    NSString *filePath;
    if([path isEqualToString:@"/ipa"] && [method isEqualToString:@"GET"]) {
        filePath = [NSString stringWithFormat:@"%@/ispy/decrypted-app.ipa", [[iSpy sharedInstance] docPath]];
        if(filePath && [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir]) {
            if(isDir == false) {
                return [[iSpyStaticFileResponse alloc] initWithFilePath:filePath forConnection:self];
            }    
        }
    }

    // Static content
    filePath = [self filePathForURI:path allowDirectory:NO];
    if(filePath && [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir])
    {

        if(isDir)
            return nil;
        else
            return [[iSpyStaticFileResponse alloc] initWithFilePath:filePath forConnection:self];
    }

    // 404
    return nil;
}

- (WebSocket *)webSocketForURI:(NSString *) path
{
    DEBUG(@"[webSocketForURI] entry");
   
    if(!path) {
        NSLog(@"[webSocketForURI] path was null");
        return nil;
    }
      

    /* Check to see if the request came from a valid origin */
    BOOL validOrigin = NO;

    NSString *origin = [request headerField:@"Origin"];
    if (origin != nil)
    {
        NSURL *url = [NSURL URLWithString:origin];
        NSString *localIp = [self getIPAddress];
        DEBUG(@"Got a request from origin %s", [[url host] UTF8String]);
        DEBUG(@"My local ip address is: %s", [localIp UTF8String]);
        if ([[url host] caseInsensitiveCompare:@"localhost"] == NSOrderedSame || [[url host] isEqualToString:@"127.0.0.1"]
                                                                              || [[url host] isEqualToString:@"::1"])
        {
            DEBUG(@"Request origin matches localhost");
            validOrigin = YES;
        }
        else if ([[url host] isEqualToString:localIp])
        {
            DEBUG(@"Request origin matches local ip: %s", [localIp UTF8String]);
            validOrigin = YES;
        }
    }
    else
    {
        DEBUG(@"Request did not contain an origin header");
        validOrigin = YES;  // If there is no Origin header the request did not come from a browser
    }


    if (validOrigin)
    {
        id webSocketHandler;

        if ([path isEqualToString:@"/jsonrpc"])
        {
            DEBUG(@"[webSocketForURI] WebSocket setup for /jsonrpc");
            webSocketHandler = [[iSpyWebSocket alloc] initWithRequest:request socket:asyncSocket];
            DEBUG(@"[webSocketForURI] Done, returning.");
            return webSocketHandler;
        }

        /*
        if ([path isEqualToString:@"/shell"])
        {
            ispy_log("WebSocket setup for /shell");
            webSocketHandler = [[ShellWebSocket alloc] initWithRequest:request socket:asyncSocket];
            [webSocketHandler setCmdLine:@"/bin/bash -l"];
            return webSocketHandler;
        }
        */

        /*
        if ([path isEqualToString:@"/cycript"])
        {
            DEBUG(@"WebSocket setup for /cycript");
            webSocketHandler = [[CycriptWebSocket alloc] initWithRequest:request socket:asyncSocket];
            [[[iSpy sharedInstance] webServer] setCycriptWebSocket:webSocketHandler];
            return webSocketHandler;
        }
        */
    }
    return nil;
}

- (NSString *)getIPAddress
{
    DEBUG(@"[getIPAddress]");
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0)
    {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL)
        {
            if(temp_addr->ifa_addr->sa_family == AF_INET)
            {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"])
                {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;

}

@end
