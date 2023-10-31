/*
    iSpy - iOS hooking framework.

    Async logging framework.
    Logs are written to <app>/Documents/ispy/logs/<facility>.log

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
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <objc/objc.h>
#include <ifaddrs.h>
#include <time.h>
#include <arpa/inet.h>
#include <mach-o/dyld.h>
#include <netinet/in.h>
#include <dispatch/dispatch.h>
#import  <Security/Security.h>
#import  <Security/SecCertificate.h>
#include <CFNetwork/CFNetwork.h>
#include <CFNetwork/CFProxySupport.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFStream.h>
#import <Foundation/NSJSONSerialization.h>
#include <pthread.h>
#import "iSpyServer/CocoaHTTPServer/Vendor/CocoaLumberjack/DDLog.h"
#import "iSpyServer/CocoaHTTPServer/Vendor/CocoaLumberjack/DDTTYLogger.h"
#import "iSpyServer/iSpyHTTPServer.h"
#import "iSpyServer/iSpyHTTPConnection.h"
#include "iSpy.common.h"
#include "iSpy.instance.h"
#include "iSpy.class.h"
#import "iSpyServer/RPCHandler.h"
#include <sys/mman.h>
#include "3rd-party/fishhook/fishhook.h"

//#define DEBUG(...) NSLog(__VA_ARGS__)
#define DEBUG(...) {}

#define MAX_LOG 0
enum { LOG_MSGSEND };

static const char* FACILITY_FILES[] = {"msgsend.log"};
static const int LOG_UMASK = 0644;
static int logFiles[MAX_LOG + 1];
static BOOL logIsInitialized = NO;

static dispatch_queue_t logQueue;
static const char *LOG_QUEUE = "com.bishopfox.iSpy.logger";
static pthread_mutex_t mutex_logLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t mutex_websocket = PTHREAD_MUTEX_INITIALIZER;

/*
 * This function is dispatched to GCD for execution
 */
static void ispy_log_write(unsigned int facility, const char *msg) {
    if (MAX_LOG < facility) {
        facility = 0;
    }

    char *line = NULL, *p = NULL;
    int lineLength;
    struct timeval tv;

    if(logFiles[facility] == -1)
        return;

    // We write pure JSON to the msgSend log file for Ojective-C events
    if(facility == LOG_MSGSEND) {
        pthread_mutex_lock(&mutex_logLock);
        write(logFiles[LOG_MSGSEND], msg, strlen(msg)); //lineLength);
        pthread_mutex_unlock(&mutex_logLock);
    } 
    // For non-msgsend events, we add a timestamp
    else {
        /* The closing ] is added to the ctime string below */
        gettimeofday(&tv, NULL);
        time_t ticks = tv.tv_sec;

        /* Don't forget the extra chars for formatting! */
        lineLength = strlen(msg) + strlen(ctime(&ticks)) + 5;
        line = (char *) malloc(lineLength + 1);
        if(!line)
            return;
        snprintf(line, lineLength, "[%s %s\n", ctime(&ticks), msg);

        // It's so dumb that we need to do this, but ctime() puts a newline at the end of its string. We strip it.
        p = line;
        while(*p && *p != '\n')
            p++;
        if(*p == '\n')
            *p = ']';

        write(logFiles[facility], line, strlen(line)); // Dump to requested log file
        free(line);
    }
}

void ispy_log_msgSend(const char *msg) {
    ispy_log_write(LOG_MSGSEND, msg);
    bf_websocket_write(msg);
}

// return the number of events in the objc_msgSend queue/log file
long get_objc_event_log_count() {
    DEBUG(@"[get_objc_event_log_count] entry");
    long count = 0, iterator = 0;
    
    NSString *baseDir = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask][0] path]; // [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask][0] path];
    NSString *fileName = [NSString stringWithFormat:@"%s", FACILITY_FILES[LOG_MSGSEND]];
    NSString *filePath = [NSString stringWithFormat:@"%@/ispy/logs/%@", baseDir, fileName];        
    const char *filePathStr = (const char *)[filePath UTF8String];
    char *data, *end, *start;
    long newLines = 0;

    int fd = open(filePathStr, O_RDONLY);
    if(fd < 0) {
        ispy_log("Abandon ship - couldn't open file: %s", filePathStr);
        return 0L;
    }

    count = iterator = lseek(fd, 0, SEEK_END);
    lseek(fd, 0, SEEK_SET);
    data = start = (char *)mmap(NULL, count, PROT_READ, MAP_FILE | MAP_SHARED, fd, 0);
    if(data == MAP_FAILED) {
        ispy_log("Abandon ship - get_objc_event_log_count couldn't mmap file: %s because: %s", filePathStr, strerror(errno));
        close(fd);
        return 0L;
    }

    // Count the lines - one per event
    end = data + count;
    while(iterator--) {
        if(*(data++) == '\n')
            newLines++;
    }

    munmap(start, count);
    close(fd);

    DEBUG(@"[get_objc_event_log_count] exit");
    return newLines;
}

NSArray *get_objc_event_log(long startEvent, long numEventsToRead) {
    DEBUG(@"[get_objc_event_log] entry");
    int fd;
    NSMutableArray *eventLog = [[NSMutableArray alloc] init];
    NSString *baseDir = [[iSpy sharedInstance] docPath];
    NSString *fileName = [NSString stringWithFormat:@"%s", FACILITY_FILES[LOG_MSGSEND]];
    NSString *filePath = [NSString stringWithFormat:@"%@/ispy/logs/%@", baseDir, fileName];        
    const char *filePathStr = (const char *)[filePath UTF8String];
    long count = 0, iterator = 0;
    char *data, *end, *start;

    fd = open(filePathStr, O_RDONLY);
    if(fd < 0) {
        //ispy_log("Abandon ship - couldn't open file: %s", filePathStr);
        return nil;
    }

    count = iterator = lseek(fd, 0, SEEK_END);
    data = start = (char *)mmap(NULL, count, PROT_READ, MAP_FILE | MAP_SHARED, fd, 0);
    if(data == MAP_FAILED) {
        //ispy_log("Abandon ship - get_objc_event_log couldn't mmap file: %s because: %s", filePathStr, strerror(errno));
        close(fd);
        return nil;
    }

    // Skip past 'startEvent' # of new lines
    end = data + count;
    if(startEvent > 0) {
        do {
            --iterator;
            if(*(data++) == '\n')
                startEvent--;       
        } while(iterator && startEvent);
    }

    // if we reached the EOF, just abort
    if(iterator == 0) {
        close(fd);
        munmap(start, count);
        //ispy_log("Abandon ship - read to end of file before reading any data!");
        return nil;
    }

    // Disable websocket squirts while we're squirting down the websocket
    //pthread_mutex_lock(&mutex_websocket);
    [[iSpy sharedInstance] setIsWebSocketLoggingEnabled:false];

    iterator = count;
    int numEventsProcessed = 0;
    char *lineBuffer, *ptr;
    while(iterator-- && (numEventsToRead > 0 || numEventsToRead == -1)) {
        if(numEventsToRead != -1)
            numEventsToRead--;

        ptr = data;
        while(*ptr != '\n' && ptr < end)
            ptr++;
        if(ptr == end) {
            //ispy_log("EOF! All done.");
            break;
        }

        size_t bufferLen = ptr - data;
        lineBuffer = (char *)malloc(bufferLen + 1);
        memset(lineBuffer, 0, bufferLen + 1);
        memcpy(lineBuffer, data, bufferLen);

        NSString *json = [NSString stringWithUTF8String:lineBuffer];
        if(!json) {
			ispy_log("Abandon ship json = nil");
			free(lineBuffer);  
            continue;  
        }

        [eventLog addObject:json]; 
        free(lineBuffer);  

        numEventsProcessed++; 
        data = ptr + 1;
    }

    // TBD: We should loop back to see if any new data arrived in the log since we last checked
    //      Keep looping until the browser is in sync with the device-sidelog

    // Re-enable the WebSocket logging
    [[iSpy sharedInstance] setIsWebSocketLoggingEnabled:true];
    //pthread_mutex_unlock(&mutex_websocket);

    //ispy_log("%d. close", count);
    munmap(start, count);
    close(fd);

    //ispy_log("%d. nslog", count);
    //ispy_log("Dumped %d entries.\nAll done!!\n", numEventsProcessed);
    
    DEBUG(@"[get_objc_event_log] exit");
    return (NSArray *)eventLog;
}

/*
 * We can use Objc here because we havn't hooked everything yet
 */
EXPORT void ispy_init_logwriter(NSString *documents) {
    if (!logIsInitialized) {

        NSError *error = nil;

        /* Check to see if our ispy directory exists, and create it if not */
        NSString *iSpyDirectory = [documents stringByAppendingPathComponent:@"/ispy/"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:iSpyDirectory]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:iSpyDirectory
                withIntermediateDirectories:NO
                attributes:nil
                error:&error];
        }
        if (error != nil) {
            NSLog(@"[iSpy][ERROR] %@", error);
        }

        /* Check to see if the <App>/Documents/ispy/logs/ directory exists, and create it if not */
        NSString *logsDirectory = [iSpyDirectory stringByAppendingPathComponent:@"/logs/"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:logsDirectory]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:logsDirectory
                withIntermediateDirectories:NO
                attributes:nil
                error:&error];
        }
        if (error != nil) {
            NSLog(@"[iSpy][ERROR] %@", error);
        }

        /* Next we create each log file, and store the FD in the static fileLogs array */
        for(unsigned int index = 0; index <= MAX_LOG; ++index) {
            NSString *fileName = [NSString stringWithFormat:@"%s", FACILITY_FILES[index]];
            NSString *filePath = [NSString stringWithFormat:@"%@/%@", logsDirectory, fileName];
            logFiles[index] = open([filePath UTF8String], O_WRONLY | O_CREAT | O_TRUNC, LOG_UMASK);
        }

        /* Initialize GCD serial queue */
        logQueue = dispatch_queue_create(LOG_QUEUE, NULL);
        logIsInitialized = YES;

        // redirect stderr to a file, thereby capturing NSLog() output
        NSString *filePath = [NSString stringWithFormat:@"%@/%s", logsDirectory, "NSLog.log"];
        unlink([filePath cStringUsingEncoding:NSASCIIStringEncoding]);
        freopen([filePath cStringUsingEncoding:NSASCIIStringEncoding], "a+", stderr);

        // start a background thread to squirt NSLog() events to the browser
        dispatch_async(logQueue, ^{
            long position = 0;
            int needToPause = 1;
            int fd, count;
            char *start, *buffer, *end, *ptr;

            while(1) {
                sleep(2);
                if([[iSpy sharedInstance] isWebSocketLoggingEnabled]) {
                    DEBUG(@"[log poll] trigger");
                    if(needToPause) {
                        sleep(1);
                        needToPause = 0;
                        position = 0;
                    }

                    fd = open([filePath cStringUsingEncoding:NSASCIIStringEncoding], O_RDONLY);
                    if(fd < 0) {
                        continue;
                    }

                    count = lseek(fd, 0, SEEK_END);
                    lseek(fd, 0, SEEK_SET);

                    if(position >= count) {
                        close(fd);
                        continue;
                    }

                    start = (char *)mmap(NULL, count, PROT_READ, MAP_FILE | MAP_SHARED, fd, 0);
                    if(start == MAP_FAILED) {
                        close(fd);
                        continue;
                    }

                    ptr = start + position;
                    end = start + count;

                    char *previousNewline = ptr - 1;
                    do {
                        while(*ptr != '\n' && ptr != end)
                            ptr++;

                        if(*ptr == '\n') {
                            size_t bufferSize = ptr - previousNewline;
                            
                            buffer = (char *)malloc(bufferSize + 1);
                            memcpy(buffer, previousNewline + 1, bufferSize);
                            buffer[bufferSize] = '\0';

                            previousNewline = ptr;
                            while(*ptr == '\n')
                                ptr++;
                            position = ptr - start;
                            
                            bf_websocket_write((const char *)buffer);
                            free(buffer);
                        } 
                    } while(ptr != end);

                    munmap(start, count);
                    close(fd);
                } else {
                    needToPause = 1;
                }
            }
            DEBUG(@"[log poll] done");
        });
    }
}

// generic logger for laziness
void ispy_log(const char *msg, ...) {
    if(!msg)
        return;

    char *msgBuffer;
    va_list args;
    va_start(args, msg);
    vasprintf(&msgBuffer, msg, args);
    va_end(args);

    if(msgBuffer) {
        //ispy_log_write(LOG_GLOBAL, msgBuffer);
        NSLog(@"%s", msgBuffer);
        free(msgBuffer);
    } 
}

@interface iSpyPOSTResponse : NSObject  <NSURLConnectionDelegate>
@end
@implementation iSpyPOSTResponse
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"[iSpyPOSTResponse] failed: %@", error);
}
@end

// This is the equivalent of [iSpyWebSocket sendMessage:@"Wakka wakka"]
extern "C" {
    void bf_websocket_write(const char *msg) {  
        DEBUG(@"[bf_websocket_write] entry");

        // XXX
        // This will stop all remote logging
        // XXX
        //return;

        if(!msg) {
            DEBUG(@"[bf_websocket_write] !msg");
            return;
        }

        // Create the request.
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", ELASTICSEARCH_URL, @"log/iSpy"]];
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
        request.HTTPMethod = @"POST";
        [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];

        NSString *encodedMsg = [NSString stringWithUTF8String:msg];
        encodedMsg = [encodedMsg stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

        NSDictionary *dictionary = @{@"messageType":@"log", @"message": encodedMsg};
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:kNilOptions error:&error];
        [request setHTTPBody:data];
        //NSLog(@"[bf_websocket_write] POSTING data: %@  //  %@", dictionary, data);

        if (!error) {
            NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
                //NSLog(@"[bf_websocket_write] Completed POST. Data: %@  //  Response: %@  //  Error: %@", data, response, error);
            }];
           [dataTask resume];
        } 

        return;

        // If there's a browser connected to iSpy, this will evaluate to true
        if([[iSpy sharedInstance] isWebSocketLoggingEnabled]) {
            DEBUG(@"[bf_websocket_write] logging is enabled!");
            // we can't cache *webServer becaue it can be invalidated by a web browser refresh
            iSpyServer *webServer = [[iSpy sharedInstance] webServer];
            if(!webServer) {
                DEBUG(@"[bf_websocket_write] !webserver");
                return;
            }

            // if we really are connected to the browser with an active WebSocket, send the JSON data to the browser
            DEBUG(@"[bf_websocket_write] iSpyWebSocket");
            WebSocket *syncSocket = [webServer iSpyWebSocket];
            if(syncSocket) {
                // convert the C string JSON to an NSString
                DEBUG(@"[bf_websocket_write] stringWithUTF8String");
                NSString *json = [NSString stringWithUTF8String:msg];
                if(!json) {
                    DEBUG(@"[bf_websocket_write] !json");
                    return;
                }

                // send it to the browser via the WebSocket
                DEBUG(@"[bf_websocket_write] msgSend");
                return;
                orig_objc_msgSend(syncSocket, @selector(sendMessage:), json);
            }
        }
        DEBUG(@"[bf_websocket_write] exit");
    }
}
