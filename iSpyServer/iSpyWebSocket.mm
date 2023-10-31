#import "iSpyWebSocket.h"
#import "../iSpy.common.h"
#import "../iSpy.class.h"


@implementation iSpyWebSocket

- (void)didOpen {
    ispy_log("Opened new WebSocket connection");
    [super didOpen];
    [[[iSpy sharedInstance] webServer] setISpyWebSocket:self];
    [[iSpy sharedInstance] setIsWebSocketLoggingEnabled:true];
}

- (void)didReceiveMessage:(NSString *)msg {
    ispy_log("WebSocket message: %s", [msg UTF8String]);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSDictionary *response = [[[iSpy sharedInstance] webServer] dispatchRPCRequest: msg];
        if (response != nil)
        {
            //ispy_log("RPC response is not nil for: %s", [msg UTF8String]);
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
            NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

            /* If the RPC request only resulted in a read, then don't broadcast the data */
            if ([response objectForKey:@"operation"] != nil && [[response objectForKey:@"operation"] isEqualToString:@"read"])
            {
                [self sendMessage: json];
            }
            /*else
            {
                [[[[iSpy sharedInstance] webServer] httpServer] ispySocketBroadcast: json];
            }
            */
        }
    });
}

- (void)didClose {
    [[iSpy sharedInstance] setIsWebSocketLoggingEnabled:false];
    [[[iSpy sharedInstance] webServer] setISpyWebSocket:nil];
    [super didClose];
    ispy_log("WebSocket connection closed");
}

@end
