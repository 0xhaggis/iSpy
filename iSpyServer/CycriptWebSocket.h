#import <Foundation/Foundation.h>

#import "../iSpy.common.h"
#import "CocoaHTTPServer/Core/WebSocket.h"
#import "iSpyHTTPServer.h"

#ifndef max
    static int __attribute((used)) max(const int x, const int y) {
        return (x > y) ? x : y;
    }
#endif

@interface CycriptWebSocket : WebSocket
{
	int _cycriptPipe[2];
	int _stdoutPipe[2];
}
@property (assign) int cycriptSocket;

-(void) pipeCycriptSocketToWebSocket;
-(BOOL) connectToCycript;

@end
