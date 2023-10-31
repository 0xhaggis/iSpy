#ifndef ___ISPY_DEFINED___
#include "iSpy.msgSend.watchlist.h"
#include "iSpy.instance.h"
#import "iSpyServer/iSpyServer.h"
#import "iSpyServer/iSpyHTTPServer.h"
#import "iSpyServer/CycriptWebSocket.h"
#import "iSpyServer/iSpyWebSocket.h"
#import "iSpyServer/RPCHandler.h"
#import "iSpy.SSLPinning.h"

#define CYCRIPT_PORT 31338

/*
    Adds a nice "containsString" method to NSString
*/
@interface NSString (iSpy)
{

}
-(BOOL) containsString:(NSString*)substring;
@end

/*
	Functionality that's exposed to Cycript.
*/
@interface iSpy : NSObject {
	@public
		ClassMap_t *_classWhitelist;
		bool msgSendLoggingEnabled;
}
@property (assign) int cycriptPort;
@property (assign) char *bundle;
@property (assign) NSString *bundleId;
@property (assign) NSString *appPath;
@property (assign) NSString *docPath;
@property (assign) NSMutableDictionary *msgSendWhitelist;
@property (assign) InstanceTracker *instanceTracker;
@property (assign) iSpyServer *webServer;
@property (assign) iSpyWebSocket *iSpyWebSocket;
@property (assign) RPCHandler *rpcHandler;
@property (assign) BOOL isWebSocketLoggingEnabled;
@property (assign) iSpySSLPinningBypass *SSLPinningBypass;
@property (assign) NSMutableDictionary *config;

//-(void)initialize2;
+(iSpy *)sharedInstance; 
-(void)initializeAllTheThings;
-(BOOL) instance_getTrackingState;
-(void) instance_enableTracking;
-(void) instance_disableTracking;
-(NSDictionary *) getNetworkInfo;
-(NSDictionary *) keyChainItems;
-(NSDictionary *) updateKeychain:(NSString *)chain forService:(NSString *)service withData:(NSData *)data;
-(NSDictionary *) infoForMethod:(SEL)selector inClass:(Class)cls;
-(NSDictionary *) infoForMethod:(SEL)selector inClass:(Class)cls isInstanceMethod:(BOOL)isInstance;
-(NSArray *) iVarsForClass:(NSString *)className;
-(NSArray *) propertiesForClass:(NSString *)className;
-(NSArray *) methodsForClass:(NSString *)className;
-(NSArray *) protocolsForClass:(NSString *)className;
-(unsigned int)countMethodsForClass:(const char *)className ;
-(NSArray *) classes;
-(NSArray *) classesWithSuperClassAndProtocolInfo;
-(NSArray *) propertiesForProtocol:(Protocol *)protocol;
-(NSArray *) methodsForProtocol:(Protocol *)protocol;
-(NSArray *) iVarListForClass:(NSString *)className;
-(NSArray *) propertyListForClass:(NSString *)className;
-(NSArray *) protocolListForClass:(NSString *)className;
-(NSArray *) methodListForClass:(NSString *)className;
-(NSDictionary *) classDumpClassFull:(NSString *)className;
-(NSDictionary *) protocolDump;
-(NSDictionary *) classDump;
-(NSDictionary *) classDumpClass:(NSString *)className;
-(NSString *) msgSend_watchlistAddClass:(NSString *) className;
-(NSString *) msgSend_watchlistAddMethod:(NSString *)methodName forClass:(NSString *)className;
-(NSString *) _msgSend_watchlistAddMethod:(NSString *)methodName forClass:(NSString *)className ofType:(struct interestingCall *)call;
-(NSString *) msgSend_addAppClassesToWhitelist;
-(NSString *) msgSend_watchlistRemoveClass:(NSString *)className;
-(NSString *) msgSend_watchlistRemoveMethod:(NSString *)methodName fromClass:(NSString *)className;
-(NSString *) msgSend_clearWhitelist;
-(void) tellBrowserToRefreshWhitelist;
+(BOOL) isClassFromApp:(NSString *)className;
-(ClassMap_t *) classWhitelist;
-(unsigned int) ASLR;
-(void) msgSend_enableLogging;
-(void) msgSend_disableLogging;
-(void) setClassWhitelist:(ClassMap_t *)classMap;
-(void *(*)(id, SEL, ...)) swizzleSelector:(SEL)originalSelector withFunction:(IMP)function forClass:(id)cls isInstanceMethod:(BOOL)isInstance;
-(void) saveState;
-(void) loadState;
-(void) sendToElasticsearch:(NSDictionary *)dict withService:(NSString *)svc;
-(bool) classDumpToElasticsearch;
@end


/*
	Helper functions.
*/

char *bf_get_type_from_signature(char *typeStr);
#else
#define ___ISPY_DEFINED___
#endif
