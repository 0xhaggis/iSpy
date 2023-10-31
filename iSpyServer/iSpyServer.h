#import "../iSpy.common.h"
#import "CocoaHTTPServer/Core/WebSocket.h"
#import "iSpyHTTPServer.h"
#import "CycriptWebSocket.h"
#import "iSpyWebSocket.h"
#import "RPCHandler.h"

/*
    Parent server that controls the HTTP server and RPC server
    and makes them talk to each other all nice like
*/
@interface iSpyServer : NSObject {

}

@property (assign) iSpyHTTPServer *httpServer;
@property (assign) iSpyWebSocket *iSpyWebSocket;
@property (assign) CycriptWebSocket *cycriptWebSocket;
//@property (assign) NSMutableDictionary *plist;
@property (assign) RPCHandler *RPCHandler;
-(void) configureWebServer;
//-(int) getListenPortFor:(NSString *) key fallbackTo: (int) fallback;
-(NSDictionary *)dispatchRPCRequest:(NSString *) JSONString;

@end
