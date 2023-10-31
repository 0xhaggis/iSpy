#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <pthread.h>
#include <errno.h>
#include <objc/message.h>
#include <sys/stat.h>
#include "3rd-party/fishhook/fishhook.h"
#include "iSpy.class.h"
#include "iSpy.common.h"
#include "iSpy.instance.h"
#include "iSpy.msgSend.h"

// Don't change the name of this function unless you also change it in iSpy.mm and iSpy.common.h
BOOL customInitialization_preflight() {
	NSLog(@"[iSpy] Running custom preflight initializors...");

	void *p = dlsym(RTLD_DEFAULT, "SSL_CTX_set_verify");
	NSLog(@"[iSpy] SSL_CTX_set_verify: %p", p);

	p = dlsym(RTLD_DEFAULT, "ssl_verify_cert_chain");
	NSLog(@"[iSpy] ssl_verify_cert_chain: %p", p);

	p = dlsym(RTLD_DEFAULT, "SSL_set_verify");
	NSLog(@"[iSpy] SSL_set_verify: %p", p);

	NSLog(@"[iSpy] Custom preflight init complete.");	
	return true;
}

// Don't change the name of this function unless you also change it in iSpy.mm and iSpy.common.h
BOOL customInitialization_postflight() {
	NSLog(@"[iSpy] Running custom postflight initializors...");

	NSLog(@"[iSpy] Custom postflight init complete.");	
	return true;
}
