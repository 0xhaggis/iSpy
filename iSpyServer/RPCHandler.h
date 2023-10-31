@interface RPCHandler : NSObject
-(NSDictionary *) setMsgSendLoggingState:(NSDictionary *) args;
-(NSDictionary *) testJSONRPC:(NSDictionary *)args;
-(NSDictionary *) ASLR:(NSDictionary *)args;
-(NSDictionary *) addMethodsToWhitelist:(NSDictionary *)args;
-(NSDictionary *) removeMethodsFromWhitelist:(NSDictionary *)args;
-(NSDictionary *) updateKeychain:(NSDictionary *)args;
-(NSDictionary *) classDumpClass:(NSDictionary *)args;
-(NSDictionary *) classDump:(NSDictionary *)args;
@end
