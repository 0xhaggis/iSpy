#import <Foundation/Foundation.h>

#import "CocoaHTTPServer/Core/WebSocket.h"
#import "../iSpy.common.h"
#import "RPCHandler.h"

@interface ShellWebSocket : WebSocket
{

}
@property (assign) int slavePTY;
@property (assign) int masterPTY;
@property (assign) NSString *cmdLine;
@property (assign) pid_t sshPID;

-(void) pipeDataToWebsocket;
-(void) runShell;
-(int) forkNewPTY;
-(void) doexec;

@end
