#import <Foundation/Foundation.h>

#import "CocoaHTTPServer/Core/HTTPConnection.h"
#import "CocoaHTTPServer/Core/HTTPMessage.h"
#import "iSpyStaticFileResponse.h"
#import "iSpyWebSocket.h"
#import "../iSpy.common.h"

@class iSpyWebSocket;

@interface iSpyHTTPConnection : HTTPConnection
{
    iSpyWebSocket *ws;
}

- (NSString *) getIPAddress;

@end
