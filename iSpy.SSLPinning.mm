#include "iSpy.common.h"
#include "iSpy.class.h"
#include "iSpy.instance.h"
#include "iSpy.SSLPinning.h"
#include "3rd-party/fishhook/fishhook.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <openssl/ssl.h>

//#define DEBUG(...) NSLog(__VA_ARGS__);
#define DEBUG(...) {}

/*
	iSpy can bypass quite a few SSL pinning implementations. 
	Enable this feature by calling [[iSpy sharedInstance] SSLPinning_enableBypass];
	It's disabled by default.
*/
static void initSSLKillSwitch2();
static void hook_AFNetworking();
static void hook_SecTrustEvaluate();
static void hook_openssl();

static void URLSession_task_didReceiveChallenge_completionHandler(id obj, SEL sel, NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, void (^handler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential));
static void (*original_URLSession_task_didReceiveChallenge_completionHandler)(id obj, SEL sel, NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, void (^handler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential)) = NULL;

static void URLSession_didReceiveChallenge_completionHandler(id obj, SEL sel, NSURLSession *session, NSURLAuthenticationChallenge *challenge, void (^handler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential));
static void (*original_URLSession_didReceiveChallenge_completionHandler)(id obj, SEL sel, NSURLSession *session, NSURLAuthenticationChallenge *challenge, void (^handler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential)) = NULL;

static OSStatus new_SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result);
static OSStatus (*original_SecTrustEvaluate)(SecTrustRef trust, SecTrustResultType *result) = NULL;

static id AFSecurityPolicy_defaultPolicy(id obj, SEL sel);
static id (*orig_AFSecurityPolicy_defaultPolicy)(id obj, SEL sel) = NULL;

static BOOL AFSecurityPolicy_evaluateServerTrustForDomain(id obj, SEL sel, SecTrustRef serverTrust, NSString *domain);
static BOOL (*original_AFSecurityPolicy_evaluateServerTrustForDomain)(id obj, SEL sel, SecTrustRef serverTrust, NSString *domain) = NULL;

typedef void SPDYSocket;
static BOOL socket_securedWithTrust(id obj, SEL sel, SPDYSocket *sock, SecTrustRef trust);
static BOOL (*original_socket_securedWithTrust)(id obj, SEL sel, SPDYSocket *sock, SecTrustRef trust) = NULL;

static void bf_SSL_CTX_set_verify(SSL_CTX *ctx, int mode, int (*verify_callback)(int, X509_STORE_CTX *));
static void (*original_SSL_CTX_set_verify)(SSL_CTX *ctx, int mode, int (*verify_callback)(int, X509_STORE_CTX *)) = NULL;

static void bf_SSL_set_verify(SSL *s, int mode, int (*verify_callback)(int, X509_STORE_CTX *));
static void (*original_SSL_set_verify)(SSL *s, int mode, int (*verify_callback)(int, X509_STORE_CTX *)) = NULL;

static long bf_SSL_get_verify_result(const SSL *ssl);
static long (*original_SSL_get_verify_result)(const SSL *ssl) = NULL;

/*
	SSLPinningBypass class
*/

@implementation iSpySSLPinningBypass

-(BOOL)enabled {
	BOOL state = false;

	if([[[[iSpy sharedInstance] config] valueForKey:ISPY_SSLPINNING_ENABLED] isEqual:ISPY_ENABLED])
		state = true;

    return state;
}

-(void)setEnabled:(id)genericState {
	BOOL state;

	// "genericState" can be a real BOOL or it can be an NSNumber representation of a BOOL. 
	// Handle accordingly.
	if((unsigned long long)genericState == 0)
		state = 0;
	else if((unsigned long long)genericState == 1)
		state = 1;
	else {
		// TODO: make safe, we could dereference something dumb and go boom
		NSNumber *n = (NSNumber *)genericState;
		state = [n boolValue];
	}

	[self setBypassSecTrustEvaluate:state];
	[self setBypassAFNetworking:state];
	[self setBypassEvaluateServerTrustForDomain:state];
	[self setBypassNSURLSession:state];
	[self setBypassSSLKillSwitch2:state];
	[self setBypassCocoaSPDY:state];
	[self setBypassOpenSSL:state];

	if(state == true)
		[[[iSpy sharedInstance] config] setValue:ISPY_ENABLED forKey:ISPY_SSLPINNING_ENABLED];
	else
		[[[iSpy sharedInstance] config] setValue:ISPY_DISABLED forKey:ISPY_SSLPINNING_ENABLED];
}

-(BOOL)swizzlePinningForClass:(Class)cls{
	const char *className = class_getName(cls);
	int swizzled = FALSE;

	if(!cls) {
		DEBUG(@"[iSpy] SSL Pinning: cls is null!");
		return FALSE;
	}

	if(className[0] == 'i' &&
		className[1] == 'S' &&
		className[2] == 'p' &&
		className[3] == 'y') {
			DEBUG(@"[iSpy] SSL Pinning: we don't care about iSpy classes, skipping %s", className);
			return FALSE;
	}

	// If we reach this point, then we know that the class was made by the app or one of its bundled frameworks
	// or that we're ignoring the class' provinence.
	DEBUG(@"[iSpy] SSL Pinning: cls %s", className);
	@try {
		DEBUG(@"[iSpy] Pinning attempt");
		if(class_getInstanceMethod(cls, @selector(evaluateServerTrust:forDomain:))) {
			NSLog(@"[iSpy] SSL Pinning: Hooking -[%s evaluateServerTrust:forDomain:]", className);
			original_AFSecurityPolicy_evaluateServerTrustForDomain = (BOOL (*)(id, SEL, SecTrustRef, NSString *))
				[[iSpy sharedInstance] swizzleSelector:@selector(evaluateServerTrust:forDomain:)
					withFunction:(IMP)AFSecurityPolicy_evaluateServerTrustForDomain
					forClass:(id)cls 
					isInstanceMethod:TRUE];
			swizzled = TRUE;
		}
		DEBUG(@"[iSpy] Pinning attempt");
		if(class_getInstanceMethod(cls, @selector(URLSession:didReceiveChallenge:completionHandler:))) {
			NSLog(@"[iSpy] NSURLSession: Hooking -[%s URLSession:didReceiveChallenge:completionHandler:]", className);
			original_URLSession_didReceiveChallenge_completionHandler = (void (*)(id, SEL, NSURLSession *, NSURLAuthenticationChallenge *, void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential)))
				[[iSpy sharedInstance] swizzleSelector:@selector(URLSession:didReceiveChallenge:completionHandler:)
					withFunction:(IMP)URLSession_didReceiveChallenge_completionHandler
					forClass:(id)cls
					isInstanceMethod:TRUE];
			swizzled = TRUE;
		}
		DEBUG(@"[iSpy] Pinning attempt");
		if(class_getInstanceMethod(cls, @selector(URLSession:task:didReceiveChallenge:completionHandler:))) {
			NSLog(@"[iSpy] NSURLSession: Hooking -[%s URLSession:task:didReceiveChallenge:completionHandler:]", className);
			original_URLSession_task_didReceiveChallenge_completionHandler = (void (*)(id, SEL, NSURLSession *, NSURLSessionTask *, NSURLAuthenticationChallenge *, void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential)))
				[[iSpy sharedInstance] swizzleSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)
					withFunction:(IMP)URLSession_task_didReceiveChallenge_completionHandler
					forClass:(id)cls
					isInstanceMethod:TRUE];
			swizzled = TRUE;
		}
		// CocoaSDPY.
		if(class_getInstanceMethod(cls, @selector(socket:securedWithTrust:))) {
			NSLog(@"[iSpy] CocoaSPDY: Hooking -[%s socket:securedWithTrust:]", className);
			original_socket_securedWithTrust = (BOOL (*)(id, SEL, SPDYSocket *, SecTrustRef))
				[[iSpy sharedInstance] swizzleSelector:@selector(socket:securedWithTrust:)
					withFunction:(IMP)socket_securedWithTrust
					forClass:(id)cls
					isInstanceMethod:TRUE];
			swizzled = TRUE;
		}
		// Facebook
		if(class_getInstanceMethod(cls, @selector(checkPinning:))) {
			NSLog(@"[iSpy] Facebook: Hooking -[%s checkPinning:]", className);
			[[iSpy sharedInstance] swizzleSelector:@selector(checkPinning:)
				withFunction:(IMP)^(id i, SEL s, void *v){return TRUE;}
				forClass:(id)cls
				isInstanceMethod:TRUE];
			swizzled = TRUE;
		}
		DEBUG(@"[iSpy] SSL Pinning: done with attempt.");
	} @catch (NSException *e) {
		DEBUG(@"iSpy] SSL Pinning: error: %@", e);
	} 
	
	return swizzled;
}

-(BOOL)isClassFromApp:(Class)cls {
	char *clsImageName;
	@try {
		clsImageName = (char *)class_getImageName(cls);
		if(!clsImageName)
			return FALSE;
		clsImageName = strdup(clsImageName);
		//DEBUG(@"[iSpy] SSL Pinning: success, got clsImageName");
	} @catch(NSException *e) {
		DEBUG(@"[iSpy] SSL Pinning: error %@", e);
		return FALSE;
	}
	
	char *clsImageNameOrig = clsImageName;
	if(!clsImageName) {
		DEBUG(@"[iSpy] SSL Pinning: couldn't get class name?!?");
		return FALSE;
	}
	DEBUG(@"[iSpy] SSL Pinning: clsImageName: %s", clsImageName);
	
	char *appImageName = strdup(_dyld_get_image_name(0));
	if(!appImageName) {
		DEBUG(@"[iSpy] SSL Pinning: couldn't get appImageName");
		free(clsImageNameOrig);
		return FALSE;
	}
	DEBUG(@"[iSpy] SSL Pinning: appImageName: %s", appImageName);

	char *ptr = strchr(appImageName, '.');
	if(	!ptr ||
		ptr[1] != 'a' ||
		ptr[2] != 'p' ||
		ptr[3] != 'p')
	{
		DEBUG(@"[iSpy] SSL Pinning: appImageName isn't at .app");
		free(clsImageNameOrig);
		free(appImageName);
		return FALSE;
	}
	*ptr = '\0';

	// If the name of the class' image path starts with "/private", skip past that part.
	// Then check for "/var" at the beginning
	clsImageName += 8;
	if(*clsImageName != '/' || clsImageName[1] != 'v') {
		DEBUG(@"[iSpy] SSL Pinning: clsImageName borked");
		free(clsImageNameOrig);
		free(appImageName);
		return FALSE;
	}

	ptr = strchr(clsImageName, '.');
	if(!ptr) {
		DEBUG(@"[iSpy] SSL Pinning: no . in clsImageName");
		free(clsImageNameOrig);
		free(appImageName);
		return FALSE;
	}
		
	if(	ptr[1] != 'a' ||
		ptr[2] != 'p' ||
		ptr[3] != 'p')
	{
		DEBUG(@"[iSpy] SSL Pinning: clsImageName no .app");
		free(clsImageNameOrig);
		free(appImageName);
		return FALSE;
	}
	*ptr = '\0';

	if(strcmp(appImageName, clsImageName) != 0) {
		DEBUG(@"[iSpy] SSL Pinning: not equal!!");
		free(clsImageNameOrig);
		free(appImageName);
		return FALSE;
	}
	
	free(clsImageNameOrig);
	free(appImageName);
	return TRUE;
}
/*
	This sets up all the different SSL pinning bypasses.
*/
-(void)installHooks {
	// Disable the SSL pinning bypasses for now
	[self setEnabled:ISPY_ENABLED];

	NSLog(@"[iSpy] SSL Pinning: Hooking HTTP delegate classes.....");
	int numberOfClasses = objc_getClassList(NULL, 0);

	DEBUG(@"[iSpy] SSL Pinning: malloc");
	Class *classList = (Class *)malloc(numberOfClasses * sizeof(Class));
	if(!classList) {
		NSLog(@"[iSpy] SSL Pinning: malloc barfed!!!!!!!!!");
		return;
	}
	DEBUG(@"[iSpy] SSL Pinning: getClassList2");
	numberOfClasses = objc_getClassList(classList, numberOfClasses);
	
	DEBUG(@"[iSpy] SSL Pinning: loop (%d classes)", numberOfClasses);

	for (int i = 0; i < numberOfClasses; i++) {
		Class cls = classList[i];
		
		DEBUG(@"[iSpy] SSL Pinning: isClassFromApp(%s)", class_getName(cls));
		if(![self isClassFromApp:cls])
			continue;

		DEBUG(@"[iSpy] SSL Pinning: YES! Seeing if it implements interesting things...	");
		[self swizzlePinningForClass:cls];
	}
	free(classList);

	NSLog(@"[iSpy] SSL Pinning: Hooking AFNetworking methods");
	hook_AFNetworking();

	NSLog(@"[iSpy] SSL Pinning: Hooking SecTrustEvaluate() function");
	hook_SecTrustEvaluate();

	NSLog(@"[iSpy] SSL Pinning: Installing SSLKillSwitch2 bypass");
	initSSLKillSwitch2();

	NSLog(@"[iSpy] SSL Pinning: Hooking openssl pinning functions");
	hook_openssl();
}
@end


/*
	NSURLSession bypasses
	Bishop Fox iSpy version by Carl
*/

// +URLSession:task:didReceiveChallenge:completionHandler:
static void URLSession_task_didReceiveChallenge_completionHandler(id obj, SEL sel, NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, void (^handler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential)) {
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassNSURLSession] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] URLSession:task:didReceiveChallenge:completionHandler: spoofing success!");
		handler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
		return;
	} else {
		original_URLSession_task_didReceiveChallenge_completionHandler(obj, sel, session, task, challenge, handler);
	}
}

// +URLSession:didReceiveChallenge:completionHandler:
static void URLSession_didReceiveChallenge_completionHandler(id obj, SEL sel, NSURLSession *session, NSURLAuthenticationChallenge *challenge, void (^handler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential)) {
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassNSURLSession] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] URLSession:didReceiveChallenge:completionHandler: spoofing success!");
		handler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
		return;
	} else {
		original_URLSession_didReceiveChallenge_completionHandler(obj, sel, session, challenge, handler);
	}
}


/*
	TrustMe SSL Bypass.
	This function is basically copy pasta from trustme: https://github.com/intrepidusgroup/trustme?source=cc
	It bypasses a few SSL pinning implementations.
*/

static OSStatus new_SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result) {
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassSecTrustEvaluate] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] Intercepting SecTrustEvaluate() call and faking a success result");
		*result = kSecTrustResultProceed;
		return errSecSuccess;
	} else {
		return original_SecTrustEvaluate(trust, result);
	}
}

static void hook_SecTrustEvaluate() {
	// Save a function pointer to the real SecTrustEvaluate() function
	original_SecTrustEvaluate = (original_SecTrustEvaluate)?original_SecTrustEvaluate:
		(OSStatus(*)(SecTrustRef trust, SecTrustResultType *result))dlsym(RTLD_DEFAULT, "SecTrustEvaluate");

	// Switch out SecTrustEvaluate for our own implementation
	rebind_symbols((struct rebinding[1]){{(char *)"SecTrustEvaluate", (void *)new_SecTrustEvaluate}}, 1); 
}

static void hook_openssl() {
	original_SSL_set_verify = (original_SSL_set_verify)?original_SSL_set_verify:
		(void(*)(SSL *s, int mode, int (*verify_callback)(int, X509_STORE_CTX *)))dlsym(RTLD_DEFAULT, "original_SSL_set_verify");
	rebind_symbols((struct rebinding[1]){{(char *)"SSL_set_verify", (void *)bf_SSL_set_verify}}, 1);

	original_SSL_CTX_set_verify = (original_SSL_CTX_set_verify)?original_SSL_CTX_set_verify:
		(void(*)(SSL_CTX *ctx, int mode, int (*verify_callback)(int, X509_STORE_CTX *)))dlsym(RTLD_DEFAULT, "original_SSL_CTX_set_verify");
	rebind_symbols((struct rebinding[1]){{(char *)"SSL_CTX_set_verify", (void *)bf_SSL_CTX_set_verify}}, 1);

	original_SSL_get_verify_result = (original_SSL_get_verify_result)?original_SSL_get_verify_result:
		(long(*)(const SSL *))dlsym(RTLD_DEFAULT, "original_SSL_get_verify_result");
	rebind_symbols((struct rebinding[1]){{(char *)"SSL_get_verify_result", (void *)bf_SSL_get_verify_result}}, 1);
}


/*
	AFNetworking SSL Pinning bypass
	Bishop Fox iSpy version by Carl
*/

#define AFSSLPinningModeNone 0

// Tell clang not to barf when passing unknown messages to id-type objects.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-method-access"

// Swizzle [AFNetworking defaultPolicy] to disable all SSL checks by default
static id AFSecurityPolicy_defaultPolicy(id obj, SEL sel) {
	id policy = orig_AFSecurityPolicy_defaultPolicy(obj, sel);

	if([[[iSpy sharedInstance] SSLPinningBypass] bypassAFNetworking] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSL pinning bypass (AFNetworking). Intercepting [AFSecurityPolicy defaultPolicy]");
		if([policy respondsToSelector:@selector(setSSLPinningMode:)])
			[policy setSSLPinningMode:AFSSLPinningModeNone];
		if([policy respondsToSelector:@selector(setAllowInvalidCertificates:)])
			[policy setAllowInvalidCertificates:TRUE];
		if([policy respondsToSelector:@selector(setValidatesDomainName:)])
			[policy setValidatesDomainName:FALSE];
		if([policy respondsToSelector:@selector(setValidatesCertificateChain:)])
			[policy setValidatesCertificateChain:FALSE];
		if([policy respondsToSelector:@selector(setPinnedPublicKeyHashes:)])
			[policy setPinnedPublicKeyHashes:nil];
		if([policy respondsToSelector:@selector(setPinnedCertificates:)])	
			[policy setPinnedCertificates:nil];
	}

	return policy;
}
#pragma clang diagnostic pop

id (*orig_AFSecurityPolicy_policyWithPinningMode)(id obj, SEL sel, int mode) = NULL;
id AFSecurityPolicy_policyWithPinningMode(id obj, SEL sel, int mode) { // class method
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassAFNetworking] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSL pinning bypass (AFNetworking). Intercepting +[AFSecurityPolicy policyWithPinningMode:]");
		mode = AFSSLPinningModeNone;
	}
	return orig_AFSecurityPolicy_policyWithPinningMode(obj, sel, mode);
}

void (*orig_AFSecurityPolicy_setSSLPinningMode)(id obj, SEL sel, int mode) = NULL;
void AFSecurityPolicy_setSSLPinningMode(id obj, SEL sel, int mode) { // instance method
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassAFNetworking] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSL pinning bypass (AFNetworking). Intercepting -[AFSecurityPolicy setSSLPinningMode:]");
		mode = AFSSLPinningModeNone;
	}
	orig_AFSecurityPolicy_setSSLPinningMode(obj, sel, mode);
}

BOOL (*orig_AFSecurityPolicy_evaluateServerTrust)(id obj, SEL sel, SecTrustRef serverTrust) = NULL;
BOOL AFSecurityPolicy_evaluateServerTrust(id obj, SEL sel, SecTrustRef serverTrust) { // instance method
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassAFNetworking] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSL pinning bypass (AFNetworking). Intercepting -[AFSecurityPolicy serverTrust:]");
		return YES;
	} else {
		return orig_AFSecurityPolicy_evaluateServerTrust(obj, sel, serverTrust);
	}
}

BOOL (*orig_AFSecurityPolicy_evaluateServerTrustForDomain)(id obj, SEL sel, SecTrustRef serverTrust, NSString *domain) = NULL;
BOOL AFSecurityPolicy_evaluateServerTrustForDomain(id obj, SEL sel, SecTrustRef serverTrust, NSString *domain) { // instance method
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassAFNetworking] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSL pinning bypass (%s). Spoofing -[%s %s] to return TRUE", object_getClassName(obj), object_getClassName(obj), sel_getName(sel));
		return YES;
	} else {
		return orig_AFSecurityPolicy_evaluateServerTrustForDomain(obj, sel, serverTrust, domain);
	}
}

static void hook_AFNetworking() {
	iSpy *mySpy = [iSpy sharedInstance];

	orig_AFSecurityPolicy_defaultPolicy = (orig_AFSecurityPolicy_defaultPolicy)?orig_AFSecurityPolicy_defaultPolicy:
		(id(*)(id, SEL))[mySpy swizzleSelector:@selector(defaultPolicy)
			withFunction:(IMP)AFSecurityPolicy_defaultPolicy
			forClass:(id)objc_getClass("AFSecurityPolicy") 
			isInstanceMethod:FALSE];
	
	orig_AFSecurityPolicy_policyWithPinningMode = (orig_AFSecurityPolicy_policyWithPinningMode)?(id(*)(id, SEL, int))orig_AFSecurityPolicy_policyWithPinningMode:
		(id(*)(id, SEL, int))[mySpy swizzleSelector:@selector(policyWithPinningMode:)
			withFunction:(IMP)AFSecurityPolicy_policyWithPinningMode
			forClass:(id)objc_getClass("AFSecurityPolicy") 
			isInstanceMethod:FALSE];

	orig_AFSecurityPolicy_setSSLPinningMode = (orig_AFSecurityPolicy_setSSLPinningMode)?orig_AFSecurityPolicy_setSSLPinningMode:
		(void(*)(id, SEL, int))[mySpy swizzleSelector:@selector(setSSLPinningMode:)
			withFunction:(IMP)AFSecurityPolicy_setSSLPinningMode
			forClass:(id)objc_getClass("AFSecurityPolicy") 
			isInstanceMethod:TRUE];

	orig_AFSecurityPolicy_evaluateServerTrust = (orig_AFSecurityPolicy_evaluateServerTrust)?orig_AFSecurityPolicy_evaluateServerTrust:
		(BOOL(*)(id, SEL, SecTrustRef))[mySpy swizzleSelector:@selector(evaluateServerTrust:)
			withFunction:(IMP)AFSecurityPolicy_evaluateServerTrust
			forClass:(id)objc_getClass("AFSecurityPolicy") 
			isInstanceMethod:TRUE];
			
	orig_AFSecurityPolicy_evaluateServerTrustForDomain = (orig_AFSecurityPolicy_evaluateServerTrustForDomain)?orig_AFSecurityPolicy_evaluateServerTrustForDomain:
		(BOOL(*)(id, SEL, SecTrustRef, NSString *))[mySpy swizzleSelector:@selector(evaluateServerTrust:ForDomain:)
			withFunction:(IMP)AFSecurityPolicy_evaluateServerTrustForDomain
			forClass:(id)objc_getClass("AFSecurityPolicy") 
			isInstanceMethod:TRUE];
}


/*
	SSLKillSwitch2 
	by iSecPartners
*/

static OSStatus (*original_SSLSetSessionOption)(SSLContextRef context,
                                                SSLSessionOption option,
                                                Boolean value);

static OSStatus replaced_SSLSetSessionOption(SSLContextRef context,
                                             SSLSessionOption option,
                                             Boolean value)
{
    // Remove the ability to modify the value of the kSSLSessionOptionBreakOnServerAuth option
    if(([[[iSpy sharedInstance] SSLPinningBypass] bypassSSLKillSwitch2] == TRUE && option == kSSLSessionOptionBreakOnServerAuth) || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
        return noErr;
    } else {
		return original_SSLSetSessionOption(context, option, value);
	}
}


static SSLContextRef (*original_SSLCreateContext)(CFAllocatorRef alloc,
                                                  SSLProtocolSide protocolSide,
                                                  SSLConnectionType connectionType);

static SSLContextRef replaced_SSLCreateContext(CFAllocatorRef alloc,
                                               SSLProtocolSide protocolSide,
                                               SSLConnectionType connectionType)
{
    SSLContextRef sslContext = original_SSLCreateContext(alloc, protocolSide, connectionType);
    
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassSSLKillSwitch2] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		// Immediately set the kSSLSessionOptionBreakOnServerAuth option in order to disable cert validation
		NSLog(@"[iSpy] SSLKillSwitch2: SSLCreateContext() bypass");
		original_SSLSetSessionOption(sslContext, kSSLSessionOptionBreakOnServerAuth, true);
	}
	return sslContext;
}

static OSStatus (*original_SSLHandshake)(SSLContextRef context);
static OSStatus replaced_SSLHandshake(SSLContextRef context)
{
    OSStatus result = original_SSLHandshake(context);
    
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassSSLKillSwitch2] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSLKillSwitch2: SSLHandshake() bypass");
		// Hijack the flow when breaking on server authentication
		if (result == errSSLServerAuthCompleted)
		{
			// Do not check the cert and call SSLHandshake() again
			return original_SSLHandshake(context);
		}
	} 
	return result;
}

static OSStatus (*original_tls_helper_create_peer_trust)(void *hdsk, bool server, SecTrustRef *trustRef);
static OSStatus replaced_tls_helper_create_peer_trust(void *hdsk, bool server, SecTrustRef *trustRef)
{
    if([[[iSpy sharedInstance] SSLPinningBypass] bypassSSLKillSwitch2] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		// Do not actually set the trustRef
		NSLog(@"[iSpy] SSLKillSwitch2: tls_helper_create_peer_trust() bypass");
		return errSecSuccess;
	} else {
		return original_tls_helper_create_peer_trust(hdsk, server, trustRef);
	}
}

static void initSSLKillSwitch2() {
	NSLog(@"[iSpy] SSLKillSwitch2 initialiation starting");
    // Fishhook-based hooking, for OS X builds; always hook
    original_SSLHandshake = (OSStatus (*)(SSLContextRef))dlsym(RTLD_DEFAULT, "SSLHandshake");
    if ((rebind_symbols((struct rebinding[1]){{(char *)"SSLHandshake", (void *)replaced_SSLHandshake}}, 1) < 0))
    {
        NSLog(@"Hooking failed.");
    }
    
    original_SSLSetSessionOption = (OSStatus (*)(SSLContextRef, SSLSessionOption, Boolean))dlsym(RTLD_DEFAULT, "SSLSetSessionOption");
    if ((rebind_symbols((struct rebinding[1]){{(char *)"SSLSetSessionOption", (void *)replaced_SSLSetSessionOption}}, 1) < 0))
    {
        NSLog(@"Hooking failed.");
    }
    
    original_SSLCreateContext = (SSLContextRef (*)(CFAllocatorRef, SSLProtocolSide, SSLConnectionType))dlsym(RTLD_DEFAULT, "SSLCreateContext");
    if ((rebind_symbols((struct rebinding[1]){{(char *)"SSLCreateContext", (void *)replaced_SSLCreateContext}}, 1) < 0))
    {
        NSLog(@"Hooking failed.");
    }
    
    original_tls_helper_create_peer_trust = (OSStatus (*)(void *, bool, SecTrustRef *))dlsym(RTLD_DEFAULT, "tls_helper_create_peer_trust");
    if ((rebind_symbols((struct rebinding[1]){{(char *)"tls_helper_create_peer_trust", (void *)replaced_tls_helper_create_peer_trust}}, 1) < 0))
    {
        NSLog(@"Hooking failed.");
    }
	NSLog(@"[iSpy] SSLKillSwitch2 initialiation complete");
}


/*
	CocoaSPDY Pinning Bypass
*/
static BOOL socket_securedWithTrust(id obj, SEL sel, SPDYSocket *sock, SecTrustRef trust) {
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassCocoaSPDY] == TRUE || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		return TRUE;
	} else {
		return original_socket_securedWithTrust(obj, sel, sock, trust);
	}
}


/*
	OpenSSL
*/

static int myVoiceIsMyPassportVerifyMe(int i, X509_STORE_CTX *x) {
	NSLog(@"[iSpy] SSL Pinning: OpenSSL: myVoiceIsMyPassport");
	return 1;
}

static void bf_SSL_CTX_set_verify(SSL_CTX *ctx, int mode, int (*verify_callback)(int, X509_STORE_CTX *)) {
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassOpenSSL] || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSL Pinning: OpenSSL: Spoofing SSL_CTX_set_verify!");
		original_SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, myVoiceIsMyPassportVerifyMe);	
	} else {
		original_SSL_CTX_set_verify(ctx, mode, verify_callback);	
	}
}

static void bf_SSL_set_verify(SSL *s, int mode, int (*verify_callback)(int, X509_STORE_CTX *)) {
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassOpenSSL] || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSL Pinning: OpenSSL: Spoofing SSL_set_verify!");
		original_SSL_set_verify(s, SSL_VERIFY_NONE, myVoiceIsMyPassportVerifyMe);
	} else {
		original_SSL_set_verify(s, mode, verify_callback);
	}
}

static long bf_SSL_get_verify_result(const SSL *ssl) {
	if([[[iSpy sharedInstance] SSLPinningBypass] bypassOpenSSL] || [[[iSpy sharedInstance] SSLPinningBypass] enabled]) {
		NSLog(@"[iSpy] SSL Pinning: OpenSSL: Spoofing SSL_get_verify_result!");
		return X509_V_OK;
	}

	return original_SSL_get_verify_result(ssl);
}
