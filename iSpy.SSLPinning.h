#define PARTIALLY_ENABLED 1
#define FULLY_ENABLED 2

void hook_SSLPinningImplementations();
static void hook_AFNetworking();
static void hook_SecTrustEvaluate();

@interface iSpySSLPinningBypass : NSObject {

}

@property(assign) BOOL bypassSecTrustEvaluate;
@property(assign) BOOL bypassAFNetworking;
@property(assign) BOOL bypassEvaluateServerTrustForDomain;
@property(assign) BOOL bypassNSURLSession;
@property(assign) BOOL bypassSSLKillSwitch2;
@property(assign) BOOL bypassCocoaSPDY;
@property(assign) BOOL bypassOpenSSL;

-(BOOL)enabled;
-(void)setEnabled:(id)state;
-(void)installHooks;

@end
