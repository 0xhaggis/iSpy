/*
 * iSpy - Bishop Fox iOS hacking/hooking framework.
 */
#import <Foundation/Foundation.h>
//#include <tr1/unordered_set>
//#include <tr1/unordered_map>
#include <unordered_set>
#include <unordered_map>
#include <fcntl.h>
#include <stdio.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <unistd.h>
#include <string>
#include <dirent.h>
#include <stdbool.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <objc/objc.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <mach-o/dyld.h>
#include <netinet/in.h>
#import  <Security/Security.h>
#import  <Security/SecCertificate.h>
#include <CFNetwork/CFNetwork.h>
#include <CFNetwork/CFProxySupport.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFStream.h>
#import  <Foundation/NSJSONSerialization.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include "iSpy.common.h"
#include "iSpy.instance.h"
#include "iSpy.class.h"
#include "iSpy.SSLPinning.h"
#include <dlfcn.h>
#include <mach-o/nlist.h>
#include <semaphore.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <QuartzCore/QuartzCore.h>
#import "3rd-party/typestring.h"
#include <execinfo.h>
#include "3rd-party/fishhook/fishhook.h"
#include "iSpy.blacklist.h"

static NSString *changeDateToDateString(NSDate *date);
static char *bf_get_friendly_method_return_type(Method method);
static char *bf_get_attrs_from_signature(char *attributeCString);

// Turn on objc_msgSend logging. Called by -[iSpy msgSend_enableLogging].
void bf_enable_msgSend_logging() {
    ispy_log("[iSpy] turning on objc_msgSend() logging");
    bf_enable_msgSend();
#ifdef __armv7__
    ispy_log("[iSpy] Turning on _stret, too");
    bf_enable_msgSend_stret();
    ispy_log("[iSpy] Done.");
#endif
}

// Turn off objc_msgSend logging.  Called by -[iSpy msgSend_disableLogging].
void bf_disable_msgSend_logging() {
    ispy_log("[iSpy] turning off objc_msgSend() logging");
    bf_disable_msgSend();
#ifdef __armv7__
    bf_disable_msgSend_stret();
#endif
}

/*
 * iSpy with my little i.
 */
@implementation iSpy

-(void) saveState {
	// Save state of the msgSend watchlist
	NSDictionary *watchlist = watchlist_copy_watchlist();
	NSString *filename = [NSString stringWithFormat:@"%@/%@", [self docPath], @"/ispy/watchlist.plist"];
	[watchlist writeToFile:filename atomically:YES];

	// Save iSpy's per-app internal configuration inside each app's Documents sandbox
	filename = [NSString stringWithFormat:@"%@/%@", [self docPath], @"/ispy/config.plist"];
	NSLog(@"[iSpy] Saving config: %@", [self config]);
	[[self config] writeToFile:filename atomically:YES];
}

-(void) applyConfig {
	
}

-(void) loadState {
	NSString *filename = [NSString stringWithFormat:@"%@/%@", [self docPath], @"/ispy/watchlist.plist"];
	NSDictionary *watchlist = [NSDictionary dictionaryWithContentsOfFile:filename];

	if(!watchlist)
		return;

	watchlist_clear_watchlist();
	NSArray *classKeys = [watchlist allKeys];
	for(int i = 0; i < [classKeys count]; i++) {
		NSArray *methods = [[watchlist objectForKey:[classKeys objectAtIndex:i]] objectForKey:@"methods"];

		for(int m = 0; m < [methods count]; m++) {
			//NSLog(@"Loading [%@ %@]", [classKeys objectAtIndex:i], [methods objectAtIndex:m]);
			[self msgSend_watchlistAddMethod:[methods objectAtIndex:m] forClass:[classKeys objectAtIndex:i]];
		}
	}

	filename = [NSString stringWithFormat:@"%@/%@", [self docPath], @"/ispy/config.plist"];
	NSData *configData = [NSData dataWithContentsOfFile:filename];
	NSDictionary *configDict = [NSKeyedUnarchiver unarchiveObjectWithData:configData];
	[self setConfig:[NSMutableDictionary dictionaryWithDictionary:configDict]];
	[self applyConfig];
}

// Does what it says on the tin.
-(void)initializeAllTheThings {
	NSLog(@"[iSpy initializeAllTheThings] Initialize all the things");

	// Allocate an object for our config
	[self setConfig:[[NSMutableDictionary alloc] init]];
	[[self config] setValue:ISPY_DISABLED forKey:ISPY_IS_ENABLED];

	NSLog(@"[iSpy initializeAllTheThings] SSL pinning bypass is ENABLED by default.");
	iSpySSLPinningBypass *SSLBypass = [[iSpySSLPinningBypass alloc] init];
	[SSLBypass installHooks];
	[SSLBypass setEnabled:ISPY_ENABLED];
	[self setSSLPinningBypass:SSLBypass];

	NSLog(@"[iSpy initializeAllTheThings] Setting the bundleIdentifier");
	[self setBundleId:[[NSBundle mainBundle] bundleIdentifier]];

	// We store the current app sandbox path 
	[self setAppPath:[[NSBundle mainBundle] bundlePath]];
	NSLog(@"[iSpy initializeAllTheThings] Application sandbox:  %@", [self appPath]);

	// We store the current Documents/ sandbox path
	//[self setDocPath:[[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject] path]];
	[self setDocPath:[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask][0] path]];
	NSLog(@"[iSpy initializeAllTheThings] Document sandbox:  %@", [self docPath]);
	chdir([[self docPath] UTF8String]);


	// There's a logging interface, too:
	//    ispy_log("Here's a pointer: %p", aPointer);
	//    ispy_log("Here's stuff getting logged to NSLog and iSpy log: %f", 3.1337);
	// Logs appear in /path/to/your/app/data/Documents/ispy/logs/. Check your NSLog() output
	// for the actual path on your device. An easy way to access this on a jailed device is to 
	// add the following lines to your app's Info.plist, which exposes the app's Documents directory to
	// applications like iFunBox:
	//     <key>UIFileSharingEnabled</key>
    //     <true/>
	NSLog(@"[iSpy initializeAllTheThings] Initializing logs @ %@", [NSString stringWithFormat:@"%@/ispy/logs/*.log", [self docPath]]);
	ispy_init_logwriter([self docPath]);
	[self setIsWebSocketLoggingEnabled:false];

	// This will replace objc_msgSend with a variant capable of selectively logging every call to pass through
	// objc_msgSend. It records arguments and return values, and it can detect interesting functions, and even 
	// allows pre-flight and post-flight code execution wrappers around Objective-C message passing. 
	// See above for where to find the log files.
	// Check iSpy.msgSend.mm and iSpy.msgSend.common.mm for code. Also iSpy.msgSend_stret.mm, but that's broken
	// and must remain disabled to prevent crashes. XXX fixme.
	ispy_log("[iSpy initializeAllTheThings] Initializing iSpy objc_msgSend hooks. Logging will remain inactive until you call -[iSpy msgSend_enableLogging]");
	self->msgSendLoggingEnabled = false;
	bf_hook_msgSend();

    ispy_log("[iSpy initializeAllTheThings] Starting up watchlist");        
    watchlist_startup();

    // Load the application's state from iSpy's prefs plist file
    //NSLog(@"[iSpy] Loading state");
	//[[iSpy sharedInstance] loadState];

	// After loading the watchlist we remove all the blacklisted classes, just to be sure.
    //ispy_log("[iSpy initializeAllTheThings] Removing blacklisted classes from watchlist");        
    //remove_blacklisted_classes_from_watchlist();

    ispy_log("[iSpy initializeAllTheThings] Starting iSpy webserver");
	[self setWebServer:[[iSpyServer alloc] init]];
	[[self webServer] setRPCHandler:[[RPCHandler alloc] init]];
	[[self webServer] configureWebServer];

	/*
	NSLog(@"[iSpy] Getting audit data...");
    NSString *auditJSONDataFileName = [ NSString stringWithFormat:@"%@/audit.json", [[[self webServer] httpServer] documentRoot]];
	if(!auditJSONDataFileName) {
		NSLog(@"[iSpy] ERROR audit.json not found");
	} else { 
		NSLog(@"[iSpy initializeAllTheThings] Reading audit events from JSON file: %s", [auditJSONDataFileName UTF8String]);        
		
		NSData *auditJSONData = [NSData dataWithContentsOfFile:auditJSONDataFileName];
		if(auditJSONData == nil) {
			NSLog(@"iSpy initializeAllTheThings] Error reading %s", [auditJSONDataFileName UTF8String]);
		} else {
			NSArray *auditJSON = (NSArray *)[NSJSONSerialization 
												JSONObjectWithData:auditJSONData
												options:(unsigned long)nil
												error:nil];

			if(auditJSON) {
				NSLog(@"[iSpy initializeAllTheThings] Adding audit data to watchlist");
				watchlist_add_audit_data_to_watchlist(auditJSON);
			} else {
				NSLog(@"[iSpy initializeAllTheThings] ERROR: Failed to convert audit data to JSON");
			}
		}
	}
	*/

	NSLog(@"[iSpy initializeAllTheThings] Setting up Cycript port");        
	[self setCycriptPort:CYCRIPT_PORT];

	//NSLog(@"[iSpy initializeAllTheThings] Initializing instance tracker");
	//[self setInstanceTracker:[InstanceTracker sharedInstance]];
	
	//NSLog(@"[iSpy initializeAllTheThings] Starting the instance tracker");
	//[[self instanceTracker] start];

	[[self config] setValue:ISPY_ENABLED forKey:ISPY_IS_ENABLED];
	NSLog(@"[iSpy initializeAllTheThings] Initialization complete.");
}


// Returns the singleton
+(iSpy *)sharedInstance {
	static iSpy *_sharedInstance = nil;
	static dispatch_once_t alloconce = 0;
	
	dispatch_once(&alloconce, ^{
		//NSLog(@"[iSpy] Instantiating iSpy one time");
		_sharedInstance = [[iSpy alloc] init];
	});

	return _sharedInstance;
}

// getter that directly plays with the instance variable, just like the objc_msgSend logging code.
-(ClassMap_t *)classWhitelist {
	return self->_classWhitelist;
}

-(void)setClassWhitelist:(ClassMap_t *)classMap {
	self->_classWhitelist = classMap;
}

// Given the name of a class, this returns true if the class is declared in the target app, false if not.
// It's waaaaaay faster than checking bundleForClass shit from the Apple runtime.
+(BOOL)isClassFromApp:(NSString *)className {
	char *appName = (char *) [[[NSProcessInfo processInfo] arguments][0] UTF8String];
	char *imageName = (char *)class_getImageName(objc_getClass([className UTF8String]));
	char *p = NULL;
	char *imageNamePtr = imageName;

	NSLog(@"app imagename: %s", _dyld_get_image_name(0));
	NSLog(@"cls imagename: %s", imageName);
	if(!imageName) {
		return false;
	}

	if(!(p = strrchr(imageName, '/'))) {
		return false;
	}

	// Support iOS 8+
	if(strncmp(imageName, "/private", 8) == 0 && strncmp(appName, "/private", 8) != 0)
		imageNamePtr += 8;

	// Strip off any trailing /Frameworks
	if(strncmp(imageNamePtr, "/var/mobile/Containers/Bundle/Application", 41) == 0) {
		char *p;
		if((p = strstr(imageNamePtr, ".app/Frameworks/")) != 0) {
			p+=4;
			*p = (char)0;
		}
	}

	//NSLog(@"isClassFromApp: '%s': imageNamePtr: %s", [className UTF8String], imageNamePtr);
	//NSLog(@"isClassFromApp: '%s':          app: %s", [className UTF8String], appName);

	if(strncmp(imageNamePtr, appName, p-imageName-1) == 0) {
		return true;
	}

	return false;
}


/*
 *
 * Methods for working with objc_msgSend logging.
 *
 */

// A lot of methods are just wrappers around pure C calls, which has the effect of exposing core iSpy features
// to Cycript for advanced use. See iSpy.msgSend.mm.
// Turn on objc_msgSend logging
-(void) msgSend_enableLogging {
	self->msgSendLoggingEnabled = true;
	bf_enable_msgSend_logging();
}

// Turn off objc_msgSend logging
-(void) msgSend_disableLogging {
	self->msgSendLoggingEnabled = false;
	bf_disable_msgSend_logging();
}

-(NSString *) msgSend_addInterestingMethodToWhitelist:(NSString *)methodName 
				forClass:(NSString *)className 
				ofClassicication:(NSString *)classification
				withDescription:(NSString *)description
				havingRisk:(NSString *)risk {

	[self _msgSend_addInterestingMethodToWhitelist:methodName 
			forClass:className 
			ofClassicication:classification 
			withDescription:description 
			havingRisk:risk
			ofType:WATCHLIST_PRESENT];

	return @"ok";
}

-(NSString *) _msgSend_addInterestingMethodToWhitelist:(NSString *)methodName 
				forClass:(NSString *)className 
				ofClassicication:(NSString *)classification
				withDescription:(NSString *)description
				havingRisk:(NSString *)risk
				ofType:(unsigned int)type {

	struct interestingCall *call = (struct interestingCall *)malloc(sizeof(struct interestingCall));
	call->risk = strdup([risk UTF8String]);
	call->className = strdup([className UTF8String]);
	call->methodName = strdup([methodName UTF8String]);
	call->description = strdup([description UTF8String]);
	call->classification = strdup([classification UTF8String]);
	call->type = (int)type;
	std::string tmpClsStr = std::string(call->className);
	std::string tmpMthStr = std::string(call->methodName);
	watchlist_add_method(&tmpClsStr, &tmpMthStr, (unsigned long)call);
	return @"ok";
}

-(void) tellBrowserToRefreshWhitelist {
	watchlist_send_websocket_update("watchlistChanged", "", "");
}

// The preferred way of adding specific methods to the objc_msgSend logging watchlist
-(NSString *) msgSend_watchlistAddMethod:(NSString *)methodName forClass:(NSString *)className {
	return [self _msgSend_watchlistAddMethod:methodName forClass:className ofType:(struct interestingCall *)WATCHLIST_PRESENT];
}

-(NSString *) _msgSend_watchlistAddMethod:(NSString *)methodName forClass:(NSString *)className ofType:(struct interestingCall *)call {
	if(!methodName || !className) {
		return @"Nil value for class or method name";
	}
	std::string *classNameString = new std::string([className UTF8String]);
	std::string *methodNameString = new std::string([methodName UTF8String]);
	if(!classNameString || !methodNameString) {
		if(methodNameString)
			delete methodNameString;
		if(classNameString)
			delete classNameString;
		return @"Error converting NSStrings to std::strings";
	}
	ispy_log("[watchlist] Adding [%s %s]", classNameString->c_str(), methodNameString->c_str());
	watchlist_add_method(classNameString, methodNameString, (unsigned long)call);
	delete methodNameString;
	delete classNameString;

	return @"ok";
}

-(NSString *)msgSend_watchlistAddClass:(NSString *) className {
	NSArray *methods = [self methodListForClass:className];

	for(int i = 0; i < [methods count]; i++) {
		[self msgSend_watchlistAddMethod:[methods objectAtIndex:i] forClass:className];
	}

	return @"ok";
}

-(NSString *) msgSend_watchlistRemoveMethod:(NSString *)methodName fromClass:(NSString *)className {
	std::string strClassName([className UTF8String]);
    std::string strMethodName([methodName UTF8String]);
    watchlist_remove_method(&strClassName, &strMethodName);
    return @"ok";
}

// remove an entire class and all its methods from the objc_msgSent watchlist
-(NSString *)msgSend_watchlistRemoveClass:(NSString *) className {
	std::string *classNameString = new std::string([className UTF8String]);
	watchlist_remove_class(classNameString);
	delete classNameString;
	return @"ok";
}

// remove all entries on the watchlist
-(NSString *) msgSend_clearWhitelist {
	watchlist_clear_watchlist();
	return @"ok";
}

// add all of the classess and methods defined by the application to the watchlist.
-(NSString *) msgSend_addAppClassesToWhitelist {
	watchlist_add_app_classes();
	return @"ok";
}

/*
 *
 * Methods for working with instaniated objects.
 *
 */
-(void) instance_enableTracking {
	[[InstanceTracker sharedInstance] start];
}

-(void) instance_disableTracking {
	[[InstanceTracker sharedInstance] stop];
}

-(BOOL) instance_getTrackingState {
	return [[InstanceTracker sharedInstance] enabled];
}

/*
 *
 * Methods for working with the keychain.
 *
 */
-(NSDictionary *)keyChainItems {
	NSLog(@"[keychain] Entry");
	NSMutableDictionary *genericQuery = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *keychainDict = [[NSMutableDictionary alloc] init];
	// genp, inet, idnt, cert, keys
	NSArray *items = [NSArray arrayWithObjects:(id)kSecClassGenericPassword, kSecClassInternetPassword, kSecClassIdentity, kSecClassCertificate, kSecClassKey, nil];
	NSArray *descs = [NSArray arrayWithObjects:(id)@"Generic Passwords", @"Internet Passwords", @"Identities", @"Certificates", @"Keys", nil];
/*	NSDictionary *kSecAttrs = @{ 
		@"ak":  @"kSecAttrAccessibleWhenUnlocked",
		@"ck":  @"kSecAttrAccessibleAfterFirstUnlock",
		@"dk":  @"kSecAttrAccessibleAlways",
		@"aku": @"kSecAttrAccessibleWhenUnlockedThisDeviceOnly",
		@"cku": @"kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly",
		@"dku": @"kSecAttrAccessibleAlwaysThisDeviceOnly"
	};*/
	int i = 0, j, count;

	count = [items count];
	do {
		NSMutableArray *keychainItems = nil;
		CFArrayRef *CFKeychainItems = nil;
		[genericQuery setObject:(id)[items objectAtIndex:i] forKey:(id)kSecClass];
		[genericQuery setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit];
		[genericQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
		[genericQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnRef];
		[genericQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];

		NSLog(@"[keychain] Calling SecItemCopyMatching");
		if (SecItemCopyMatching((CFDictionaryRef)genericQuery, (CFTypeRef *)&CFKeychainItems) == noErr) {
			keychainItems = [[NSArray arrayWithArray:(NSArray *)CFKeychainItems] mutableCopy];

			// Loop through the keychain entries, logging them.
			for(j = 0; j < [keychainItems count]; j++) {
				for(NSString *key in [[keychainItems objectAtIndex:j] allKeys]) {
					/*// We don't need the v_Ref attribute; it's just an another representation of v_data that won't serialize to JSON. Pfft.
					if([key isEqual:@"v_Ref"]) {
						[[keychainItems objectAtIndex:j] removeObjectForKey:key];
						continue;
					}*/

					id obj = [[keychainItems objectAtIndex:j] objectForKey:key];
					//NSLog(@"Got %@ // class: %@", obj, [obj class]);

					// Is this some kind of NSData/__NSFSData/etc?
					// NSJSONSerializer won't parse NSDate or NSData, so we convert any of those into NSString for later JSON-ification.
					if(	[obj class] == objc_getClass("__NSData") ||
						[obj class] == objc_getClass("__NSCFData")) {
						NSString *str = [[NSString alloc] initWithData:obj encoding:NSUTF8StringEncoding];
						if(str == nil)
							str = @"";
						[[keychainItems objectAtIndex:j] setObject:str forKey:key];
					}

					// how about NSDate?
					else if([obj class] == objc_getClass("__NSDate")) {
						[[keychainItems objectAtIndex:j] setObject:changeDateToDateString(obj) forKey:key];
					}

					// __NSCFType won't serialize, either
					else if([obj class] == objc_getClass("__NSCFType")) {
						[[keychainItems objectAtIndex:j] setObject:[obj description] forKey:key];	
					}

					// add a human-readable kSecAttr value to the "v_pdmn" key. It's only for UI purposes.
					//[[keychainItems objectAtIndex:j] setObject:[kSecAttrs objectForKey:[[keychainItems objectAtIndex:j] objectForKey:@"pdmn"]] forKey:@"v_pdmn"];

					// Security check. Report any occurences of insecure storage.
					/*
					NSString *attr = [kSecAttrs objectForKey:[[keychainItems objectAtIndex:j] objectForKey:@"pdmn"]];
					if([attr isEqual:@"kSecAttrAccessibleAlways"] || [attr isEqual:@"kSecAttrAccessibleAlwaysThisDeviceOnly"]) {
				   		NSString *strName;
				   		if([[[keychainItems objectAtIndex:j] objectForKey:@"acct"] respondsToSelector:@selector(bytes)]) {
							NSString *str = [[NSString alloc] initWithData:[[keychainItems objectAtIndex:j] objectForKey:@"acct"] encoding:NSUTF8StringEncoding];
							if(str == nil)
								str = @"";
							strName = str;
						} else {
							strName = [NSString stringWithFormat:@"%@", [[keychainItems objectAtIndex:j] objectForKey:@"acct"]];
						}

						ispy_log("[Insecure Keychain Storage] Key \"%s\" has attribute \"%s\" on item \"%s\"", [key UTF8String], [attr UTF8String], [strName UTF8String]);
					}
					*/
				}
			}
		} else {
			keychainItems = (NSMutableArray *)@[];
		}
		//[keychainDict setObject:[[NSArray arrayWithArray:keychainItems] copy] forKey:[descs objectAtIndex:i]];
		[keychainDict setObject:[NSArray arrayWithArray:keychainItems] forKey:[descs objectAtIndex:i]];
	} while(++i < count);

	return [NSDictionary dictionaryWithDictionary:keychainDict];
}

-(NSDictionary *) updateKeychain:(NSString *)chain forService:(NSString *)service withData:(NSData *)data {
	NSLog(@"[keychain] Update: %@ / %@ / %@", chain, service, data);
	NSMutableDictionary *genericQuery = [[NSMutableDictionary alloc] init];
	NSDictionary *lookup = @{
		@"Generic Passwords": (id)kSecClassGenericPassword,
		@"Internet Passwords": (id)kSecClassInternetPassword,
		@"Identities": (id)kSecClassIdentity,
		@"Certificates": (id)kSecClassCertificate,
		@"Keys": (id)kSecClassKey
	};

	id keychainClass = [lookup objectForKey:chain];
	NSMutableArray *keychainItems = nil;
	CFArrayRef *CFKeychainItems = nil;

	[genericQuery setObject:(id)keychainClass forKey:(id)kSecClass];
	[genericQuery setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
	[genericQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
	[genericQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnRef];
	[genericQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];

	NSLog(@"[keychain] Calling SecItemCopyMatching");
	if (SecItemCopyMatching((CFDictionaryRef)genericQuery, (CFTypeRef *)&CFKeychainItems) == noErr) {
		keychainItems = [[NSArray arrayWithArray:(NSArray *)CFKeychainItems] mutableCopy];
		ispy_log("[keychain] Update found item: %@", keychainItems);
	} else {
		ispy_log("[keychain] Failed to get items for update");
	}
/*
			// Loop through the keychain entries, logging them.
			for(j = 0; j < [keychainItems count]; j++) {
				for(NSString *key in [[keychainItems objectAtIndex:j] allKeys]) {
					id obj = [[keychainItems objectAtIndex:j] objectForKey:key];
					//NSLog(@"Got %@ // class: %@", obj, [obj class]);

					// Is this some kind of NSData/__NSFSData/etc?
					// NSJSONSerializer won't parse NSDate or NSData, so we convert any of those into NSString for later JSON-ification.
					if(	[obj class] == objc_getClass("__NSData") ||
						[obj class] == objc_getClass("__NSCFData")) {
						NSString *str = [[NSString alloc] initWithData:obj encoding:NSUTF8StringEncoding];
						if(str == nil)
							str = @"";
						[[keychainItems objectAtIndex:j] setObject:str forKey:key];
					}

					// how about NSDate?
					else if([obj class] == objc_getClass("__NSDate")) {
						[[keychainItems objectAtIndex:j] setObject:changeDateToDateString(obj) forKey:key];
					}

					// __NSCFType won't serialize, either
					else if([obj class] == objc_getClass("__NSCFType")) {
						[[keychainItems objectAtIndex:j] setObject:[obj description] forKey:key];	
					}
				}
			}
		} else {
			keychainItems = (NSMutableArray *)@[];
		}
		[keychainDict setObject:[[NSArray arrayWithArray:keychainItems] copy] forKey:[descs objectAtIndex:i]];
	} while(++i < count);
	*/

	return (NSDictionary *)@{ @"keychainItems": keychainItems};
}


// Return the current ASLR slide.
-(unsigned int)ASLR {
	unsigned int slide = (unsigned int)_dyld_get_image_vmaddr_slide(0);
	
	// security check - log all instances of non-ASLR apps
	if(slide == 0)
		ispy_log("[Insecure ASLR] ASLR is disabled for this app. Slide = 0.");

	return slide; 
}



/*
 *
 * Methods for working with methods
 *
 */

/*
Returns a NSDictionary like this:
{
	"name" = "doSomething:forString:withChars:",

	"parameters" = {
		// name = type
		"arg1" = "id",
		"arg2" = "NSString *",
		"arg3" = "char *"
	},

	"returnType" = "void";
}
*/
-(NSDictionary *)infoForMethod:(SEL)selector inClass:(Class)cls {
	return [self infoForMethod:selector inClass:cls isInstanceMethod:1];
}

-(NSDictionary *)infoForMethod:(SEL)selector inClass:(Class)cls isInstanceMethod:(BOOL)isInstance {
	Method method = nil;
	BOOL isInstanceMethod = true;
	NSMutableArray *parameters = [[NSMutableArray alloc] init];
	NSMutableDictionary *methodInfo = [[NSMutableDictionary alloc] init];
	int numArgs, k;
	NSString *returnType;
	char *freeMethodName, *methodName, *tmp;

	if(cls == nil || selector == nil)
		return nil;

	//NSLog(@"[iSpy infoForMethod] instancesRespondToSelector");
	if([cls instancesRespondToSelector:selector] == YES) {
		//NSLog(@"[iSpy infoForMethod] class_getInstanceMethod");
		method = class_getInstanceMethod(cls, selector);
	} else if([cls respondsToSelector:selector] == YES) {
		//NSLog(@"[iSpy infoForMethod] class_getClassMethod");
		method = class_getClassMethod(cls, selector);
		isInstanceMethod = false;
	} else {
		NSLog(@"Method not found");
		return nil;
	}

	if (method == nil) {
		NSLog(@"Method returned nil");
		return nil;
	}

	//NSLog(@"[iSpy infoForMethod] method_getNumberOfArguments");
	numArgs = method_getNumberOfArguments(method);

	// get the method's name as a (char *)
	//NSLog(@"[iSpy infoForMethod] strdup");
	freeMethodName = methodName = (char *)strdup(sel_getName(method_getName(method)));

	// cycle through the paramter list for this method.
	// start at k=2 so that we omit Cls and SEL, the first 2 args of every function/method
	//NSLog(@"do arg loop");
	for(k=2; k < numArgs; k++) {
		char tmpBuf[256]; // safe and reasonable limit on var name length
		char *type;
		char *name;
		NSMutableDictionary *param = [[NSMutableDictionary alloc] init];

		//NSLog(@"[iSpy infoForMethod] strsep");
		name = strsep(&methodName, ":");
		if(!name) {
			NSLog(@"um, so p=NULL in arg printer for class methods... weird.");
			continue;
		}

		//NSLog(@"[iSpy infoForMethod] method_getArgumentType");
		method_getArgumentType(method, k, tmpBuf, 255);

		//NSLog(@"[iSpy infoForMethod] bf_get_type_from_signature");
		if((type = (char *)bf_get_type_from_signature(tmpBuf))==NULL) {
			ispy_log("Out of mem?");
			break;
		}

		//NSLog(@"[iSpy infoForMethod] set param");
		[param setObject:[NSString stringWithUTF8String:type] forKey:@"type"];
		[param setObject:[NSString stringWithUTF8String:name] forKey:@"name"];
		//NSLog(@"[iSpy infoForMethod] set parameters");
		[parameters addObject:param];
		free(type);
	} // args

	//NSLog(@"[iSpy infoForMethod] bf_get_friendly_method_return_type");
	tmp = (char *)bf_get_friendly_method_return_type(method);

	if (!tmp) {
		returnType = @"XXX_unknown_type_XXX";
	} else {
		//NSLog(@"[iSpy infoForMethod] returnType free");
		returnType = [NSString stringWithUTF8String:tmp];
		free(tmp);
	}

	//NSLog(@"[iSpy infoForMethod] set methodInfo");
	[methodInfo setObject:parameters forKey:@"parameters"];
	[methodInfo setObject:returnType forKey:@"returnType"];
	[methodInfo setObject:[NSString stringWithUTF8String:freeMethodName] forKey:@"name"];
	[methodInfo setObject:[NSNumber numberWithInt:isInstanceMethod] forKey:@"isInstanceMethod"];
	[methodInfo setObject:[NSString stringWithUTF8String:sel_getName(selector)] forKey:@"selector"];
	//NSLog(@"[iSpy infoForMethod] free");
	free(freeMethodName);

	//return [methodInfo copy];
	return methodInfo;
}


/*
 *
 * Methods for working with classes
 *
 */

 -(NSArray *)iVarListForClass:(NSString *)className {
	unsigned int iVarCount = 0, j;
	Ivar *ivarList = class_copyIvarList(objc_getClass([className UTF8String]), &iVarCount);
	NSMutableArray *iVars = [[NSMutableArray alloc] init];

	if(!ivarList)
		return @[];

	for(j = 0; j < iVarCount; j++) {
		char *name = (char *)ivar_getName(ivarList[j]);
		[iVars addObject:[NSString stringWithUTF8String:name]];
	}
	//return [iVars copy];
	return iVars;
}


-(NSArray *)iVarsForClass:(NSString *)className {
	unsigned int iVarCount = 0, j;
	Ivar *ivarList = class_copyIvarList(objc_getClass([className UTF8String]), &iVarCount);
	NSMutableArray *iVars = [[NSMutableArray alloc] init];

	//NSLog(@"[iSpy iVarsForClass] ivarList");
	if(!ivarList)
		return @[]; //[iVars copy];

	//NSLog(@"[iSpy iVarsForClass] Loop");
	for(j = 0; j < iVarCount; j++) {
		NSMutableDictionary *iVar = [[NSMutableDictionary alloc] init];

		//NSLog(@"[iSpy iVarsForClass] ivar_getName");
		char *name = (char *)ivar_getName(ivarList[j]);
		if(!name)
			continue;

		//NSLog(@"[iSpy iVarsForClass] ivar_getTypeEncoding");
		char *typeEncoding = (char *)ivar_getTypeEncoding(ivarList[j]);
		if(!typeEncoding)
			continue;

		//NSLog(@"[iSpy iVarsForClass] bf_get_type_from_signature");
		char *type = bf_get_type_from_signature(typeEncoding);
		if(!type) {
			free(type);
			continue;
		}

		//NSLog(@"[iSpy iVarsForClass] Set");
		[iVar setObject:[NSString stringWithUTF8String:type] forKey:@"type"];
		[iVar setObject:[NSString stringWithUTF8String:typeEncoding] forKey:@"typeEncoding"];
		[iVar setObject:[NSString stringWithUTF8String:name] forKey:@"name"];
		[iVars addObject:iVar];

		//NSLog(@"[iSpy iVarsForClass] free and loop");
		free(type);
	}
	//return [iVars copy];
	return iVars;
}

-(NSArray *)propertyListForClass:(NSString *)className {
	unsigned int propertyCount = 0, j;
	objc_property_t *propertyList = class_copyPropertyList(objc_getClass([className UTF8String]), &propertyCount);
	NSMutableArray *properties = [[NSMutableArray alloc] init];

	if(!propertyList)
		return @[];

	for(j = 0; j < propertyCount; j++) {
		objc_property_t objcProp = propertyList[j];

		char *name = (char *)property_getName(objcProp);
		[properties addObject:[NSString stringWithUTF8String:name]];
	}
	//return [properties copy];
	return properties;
}

-(NSArray *)propertiesForClass:(NSString *)className {
	unsigned int propertyCount = 0, j;
	objc_property_t *propertyList = class_copyPropertyList(objc_getClass([className UTF8String]), &propertyCount);
	NSMutableArray *properties = [[NSMutableArray alloc] init];

	if(!propertyList)
		return @[]; //[properties copy];

	for(j = 0; j < propertyCount; j++) {
		NSMutableDictionary *property = [[NSMutableDictionary alloc] init];
		objc_property_t objcProp = propertyList[j];

		char *encodedAttributes = (char *)property_getAttributes(objcProp);
		char *name = (char *)property_getName(objcProp);
		char *attr = bf_get_attrs_from_signature(encodedAttributes); 
		NSArray *types = ParseTypeString([NSString stringWithUTF8String:encodedAttributes]);

		[property setObject:[NSString stringWithUTF8String:attr] forKey:@"attr"];
		[property setObject:[NSString stringWithUTF8String:name] forKey:@"name"];
		[property setObject:[types objectAtIndex:0] forKey:@"type"];
		[properties addObject:property];
		
		free(attr);
	}
	//return [properties copy];
	return properties;
}

-(NSArray *)protocolListForClass:(NSString *)className {
	unsigned int protocolCount = 0, j;
	Protocol **protocols = class_copyProtocolList(objc_getClass([className UTF8String]), &protocolCount);
	NSMutableArray *protocolList = [[NSMutableArray alloc] init];

	if(protocolCount <= 0)
		return @[];

	// some of this code was inspired by (and a little of it is copy/pasta) https://gist.github.com/markd2/5961219
	for(j = 0; j < protocolCount; j++) {
		const char *protocolName = protocol_getName(protocols[j]); 
		unsigned int adoptedProtocolsCount;
		Protocol **adoptedProtocols = protocol_copyProtocolList(protocols[j], &adoptedProtocolsCount);

		NSMutableArray *adoptedProtocolList = [[NSMutableArray alloc] init];
		for(int i = 0; i < adoptedProtocolsCount; i++) {
			const char *adoptedProtocolName = protocol_getName(adoptedProtocols[i]);
			if(!adoptedProtocolName)
				continue; // skip broken names
			[adoptedProtocolList addObject:[NSString stringWithUTF8String:adoptedProtocolName]];
		}
		free(adoptedProtocols);

		[protocolList addObject:[NSString stringWithUTF8String:protocolName]];
	}
	free(protocols);
	//return [protocolList copy];
	return protocolList;
}

-(NSArray *)protocolsForClass:(NSString *)className {
	unsigned int protocolCount = 0, j;
	Protocol **protocols = class_copyProtocolList(objc_getClass([className UTF8String]), &protocolCount);
	NSMutableArray *protocolList = [[NSMutableArray alloc] init];

	if(protocolCount <= 0)
		return @[];

	// some of this code was inspired by (and a little of it is copy/pasta) https://gist.github.com/markd2/5961219
	for(j = 0; j < protocolCount; j++) {
		NSMutableArray *adoptees;
		NSMutableDictionary *protocolInfoDict = [[NSMutableDictionary alloc] init];
		const char *protocolName = protocol_getName(protocols[j]); 
		unsigned int adopteeCount;
		Protocol **adopteesList = protocol_copyProtocolList(protocols[j], &adopteeCount);

		adoptees = [[NSMutableArray alloc] init];
		for(int i = 0; i < adopteeCount; i++) {
			const char *adopteeName = protocol_getName(adopteesList[i]);
			if(!adopteeName)
				continue; // skip broken names
			[adoptees addObject:[NSString stringWithUTF8String:adopteeName]];
		}
		free(adopteesList);

		[protocolInfoDict setObject:[NSString stringWithUTF8String:protocolName] forKey:@"protocolName"];
		[protocolInfoDict setObject:adoptees forKey:@"adoptees"];
		[protocolInfoDict setObject:[self propertiesForProtocol:protocols[j]] forKey:@"properties"];
		[protocolInfoDict setObject:[self methodsForProtocol:protocols[j]] forKey:@"methods"];

		[protocolList addObject:protocolInfoDict];
	}
	free(protocols);
	//return [protocolList copy];
	return protocolList;
}

-(unsigned int)countMethodsForClass:(const char *)className {
	unsigned int numClassMethods = 0;
	unsigned int numInstanceMethods = 0;
	Class c;
	Method *classMethodList = NULL;
	Method *instanceMethodList = NULL;

	Class cls = objc_getClass(className);
	if(cls == nil)
		return 0; 

	c = object_getClass(cls);
	if(c) {
		classMethodList = class_copyMethodList(c, &numClassMethods);
	}
	else {
		classMethodList = NULL;
		numClassMethods = 0;
	}

	instanceMethodList = class_copyMethodList(cls, &numInstanceMethods);

	return numInstanceMethods + numClassMethods;
}

/*
 * returns an NSArray of NSDictionaries, each containing metadata (name, class/instance, etc) about a method for the specified class.
 */
-(NSArray *)methodsForClass:(NSString *)className {
	unsigned int numClassMethods = 0;
	unsigned int numInstanceMethods = 0;
	unsigned int i;
	NSMutableArray *methods = [[NSMutableArray alloc] init];
	Class c;
	char *classNameUTF8;
	Method *classMethodList = NULL;
	Method *instanceMethodList = NULL;

	if(!className) {
		NSLog(@"[methodsForClass] className was null");
		return @[]; 
	}

	//NSLog(@"[iSpy methodsForClass] Doing %@", className);

	if((classNameUTF8 = (char *)[className UTF8String]) == NULL) {
		NSLog(@"[methodsForClass] classNameUTF8 was null");
		return @[]; 
	}

	//NSLog(@"[iSpy methodsForClass] objc_getClass for %s", classNameUTF8);
	Class cls = objc_getClass(classNameUTF8);
	if(cls == nil) {
		NSLog(@"[methodsForClass] cls was nil");
		return @[]; 
	}

	//NSLog(@"[iSpy methodsForClass] object_getClass for %@", cls);
	c = object_getClass(cls);
	if(c) {
		//NSLog(@"[iSpy methodsForClass] class_copyMethodList for %@", c);
		classMethodList = class_copyMethodList(c, &numClassMethods);
	}
	else {
		//NSLog(@"[iSpy methodsForClass] !c");
		classMethodList = NULL;
		numClassMethods = 0;
	}

	//NSLog(@"[iSpy methodsForClass] class_copyMethodList for %@", cls);
	instanceMethodList = class_copyMethodList(cls, &numInstanceMethods);

	if(	(classMethodList == nil && instanceMethodList == nil) ||
		(numClassMethods == 0 && numInstanceMethods ==0)) {
		//NSLog(@"[methodsForClass] WTF!!!");
		return @[];
	}
		
	if(classMethodList != NULL && numClassMethods > 0) {
		//NSLog(@"[iSpy methodsForClass] looping classMethodList (%d)", numClassMethods);
		for(i = 0; i < numClassMethods; i++) {
			if(!classMethodList[i])
				continue;
			SEL sel = method_getName(classMethodList[i]);
			//char *name = sel_getName(sel);
			//if(name[0] == 'c' && name[1] == 'y' && name[2] == '$')
			if(!sel)
				continue;
			NSDictionary *methodInfo = [self infoForMethod:sel inClass:cls isInstanceMethod:false];
			if(methodInfo != nil)
				[methods addObject:methodInfo];
		}
		free(classMethodList);
	}

	if(instanceMethodList != NULL && numInstanceMethods > 0) {
		//NSLog(@"[iSpy methodsForClass] looping instances (%d)", numInstanceMethods);
		for(i = 0; i < numInstanceMethods; i++) {
			if(!instanceMethodList[i])
				continue;
			//NSLog(@"[iSpy methodsForClass] method_getName");
			SEL sel = method_getName(instanceMethodList[i]);
			if(!sel)
				continue;
			//NSLog(@"[iSpy methodsForClass] infoForMethod: %s",  sel_getName(sel));
			NSDictionary *methodInfo = [self infoForMethod:sel inClass:cls isInstanceMethod:true];
			//NSLog(@"[iSpy methodsForClass] back");
			if(methodInfo)
				[methods addObject:methodInfo];
		}
		free(instanceMethodList);
	}

	//NSLog(@"[iSpy methodsForClass] Returning");
	if([methods count] <= 0) {
		NSLog(@"[methodsForClass] method count = 0");
		return @[];
	}
	else {
		//return [methods copy];
		return methods;
	}
}

/*
 * Returns an NSArray of NSString names, each of which is a method name for the specified class.
 * You should release the returned NSArray.
 */
-(NSArray *)methodListForClass:(NSString *)className {
	unsigned int numClassMethods = 0;
	unsigned int numInstanceMethods = 0;
	unsigned int i;
	NSMutableArray *methods = [[NSMutableArray alloc] init];
	Class c;
	char *classNameUTF8;
	Method *classMethodList = NULL;
	Method *instanceMethodList = NULL;

	if(!className)
		return nil; //[methods copy];

	if((classNameUTF8 = (char *)[className UTF8String]) == NULL)
		return nil; //[methods copy];

	Class cls = objc_getClass(classNameUTF8);
	if(cls == nil)
		return nil; //[methods copy];

	c = object_getClass(cls);
	if(c) {
		classMethodList = class_copyMethodList(c, &numClassMethods);
	}
	else {
		classMethodList = NULL;
		numClassMethods = 0;
	}

	instanceMethodList = class_copyMethodList(cls, &numInstanceMethods);

	if(	(classMethodList == nil && instanceMethodList == nil) ||
		(numClassMethods == 0 && numInstanceMethods ==0))
		return nil;

	if(classMethodList != NULL) {
		for(i = 0; i < numClassMethods; i++) {
			if(!classMethodList[i])
				continue;
			SEL sel = method_getName(classMethodList[i]);
			if(sel)
				[methods addObject:[NSString stringWithUTF8String:sel_getName(sel)]];
		}
		free(classMethodList);
	}

	if(instanceMethodList != NULL) {
		for(i = 0; i < numInstanceMethods; i++) {
			if(!instanceMethodList[i])
				continue;
			SEL sel = method_getName(instanceMethodList[i]);
			if(sel)
				[methods addObject:[NSString stringWithUTF8String:sel_getName(sel)]];
		}
		free(instanceMethodList);
	}
	if([methods count] <= 0)
		return nil;
	else
		//return [methods copy];
		return methods;
}

-(NSArray *)classes {
	Class * classes = NULL;
	NSMutableArray *classArray = [[NSMutableArray alloc] init];
	int numClasses;

	numClasses = objc_getClassList(NULL, 0);
	if(numClasses <= 0)
		return nil; //[classArray copy];

	if((classes = (Class *)malloc(sizeof(Class) * numClasses)) == NULL)
		//return [classArray copy];
		return classArray;

	objc_getClassList(classes, numClasses);

	int i=0;
	while(i < numClasses) {
		NSString *className = [NSString stringWithUTF8String:class_getName(classes[i])];
		if([iSpy isClassFromApp:className])
			[classArray addObject:className];
		i++;
	}
	//return [classArray copy];
	return classArray;
}

-(NSArray *)classesWithSuperClassAndProtocolInfo {
	Class * classes = NULL;
	NSMutableArray *classArray = [[NSMutableArray alloc] init];
	int numClasses;
	unsigned int numProtocols;

	numClasses = objc_getClassList(NULL, 0);
	if(numClasses <= 0) {
		NSLog(@"No classes");
		return nil; //[classArray copy];
	} else {
		NSLog(@"Got %d classes", numClasses);
	}

	if((classes = (Class *)malloc(sizeof(Class) * numClasses)) == NULL)
		//return [classArray copy];
		return classArray;

	objc_getClassList(classes, numClasses);

	int i=0;
	while(i < numClasses) {
		NSString *className = [NSString stringWithUTF8String:class_getName(classes[i])];
		NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

		if([iSpy isClassFromApp:className]) {
			Protocol **protocols = class_copyProtocolList(classes[i], &numProtocols);
			Class superClass = class_getSuperclass(classes[i]);
			char *superClassName = NULL;

			if(superClass)
				superClassName = (char *)class_getName(superClass);

			[dict setObject:className forKey:@"className"];
			[dict setObject:[NSString stringWithUTF8String:superClassName] forKey:@"superClass"];

			NSMutableArray *pr = [[NSMutableArray alloc] init];
			if(numProtocols) {
				for(int i = 0; i < numProtocols; i++) {
					[pr addObject:[NSString stringWithUTF8String:protocol_getName(protocols[i])]];
				}
				free(protocols);
			}
			[dict setObject:pr forKey:@"protocols"];
			[classArray addObject:dict];
		}
		i++;
	}
	//return [classArray copy];
	return classArray;
}

/*
 * The following function returns an NSDictionary, like so:
{
	"MyClass1": {
		"className": "MyClass1",
		"superClass": "class name",
		"methods": {

		},
		"ivars": {

		},
		"properties": {

		},
		"protocols": {

		}
	},
	"MyClass2": {
		"methods": {

		},
		"ivars": {

		},
		"properties": {

		},
		"protocols": {

		}
	},
	...
}
*/

-(bool) classDumpToElasticsearch {
	NSMutableDictionary *classDumpDict = [[NSMutableDictionary alloc] init];
	NSArray *clsList = [self classes]; // returns an array of class names

	if(!classDumpDict || !clsList)
		return false;

	NSLog(@"[iSpy] classDumpToElasticsearch processing %ld classes", (unsigned long)[clsList count]);
	for(int i = 0; i < [clsList count]; i++) {
		NSString *className = [clsList objectAtIndex:i];
		if(className) {
			NSDictionary *cls = [self classDumpClassFull:className];	
			if(cls) {
				[self sendToElasticsearch:cls withService:[NSString stringWithFormat:@"iSpy/class/%@", className]];
			}
		}
	}
	
	return true;
}


-(NSDictionary *)classDump {
	NSMutableDictionary *classDumpDict = [[NSMutableDictionary alloc] init];
	NSArray *clsList = [self classes]; // returns an array of class names

	if(!classDumpDict || !clsList)
		return @{};

	NSLog(@"[iSpy] classDump processing %ld classes", (unsigned long)[clsList count]);
	for(int i = 0; i < [clsList count]; i++) {
		NSString *className = [clsList objectAtIndex:i];
		if(className) {
			NSDictionary *cls = [self classDumpClassFull:className];	
			if(cls) {
				[classDumpDict setObject:cls forKey:className];
			}
		}
	}

	return [classDumpDict copy];
	//return classDumpDict;
}

// This function does the same thing, only for a single specified class name.
-(NSDictionary *)classDumpClassFull:(NSString *)className {
	unsigned int numProtocols;
	static const char *fakeSuperClassName = "NSObject /* NSobject is the root and doesn't really inherit itself, it just implements the NSObject protocol: */";
	char *superClassName = NULL;
	NSMutableDictionary *cls = [[NSMutableDictionary alloc] init];

	Class theClass = objc_getClass([className UTF8String]);
	if(!theClass) {
		NSLog(@"[iSpy classDumpClassFull] theClass is nil"); 
		return nil;
	} else {
		//NSLog(@"[iSpy classDumpClassFull] dumping class: \"%s\"", class_getName(theClass));
	}

	//NSLog(@"[iSpy classDumpClassFull] superclass...");
	Class superClass = class_getSuperclass(theClass);
	if(superClass) {
		superClassName = (char *)class_getName(superClass);
	} else {
		NSLog(@"[RPC] superClassName is going to be null, fixing");
		superClassName = (char *)fakeSuperClassName;
	}

	//NSLog(@"[iSpy classDumpClassFull] protocol...");
	Protocol **protocols = class_copyProtocolList(theClass, &numProtocols);
	NSMutableArray *pr = [[NSMutableArray alloc] init];
	if(numProtocols) {
		for(int i = 0; i < numProtocols; i++) {
			[pr addObject:[NSString stringWithUTF8String:protocol_getName(protocols[i])]];
		}
		free(protocols);
	}

	//NSLog(@"[iSpy classDumpClassFull] method");
	NSArray *methodList = [self methodsForClass:className];
	if(!methodList)
		methodList = @[];

	//NSLog(@"[iSpy classDumpClassFull] copy");
	//NSLog(@"[RPC] Setting cls");
	//NSLog(@"[iSpy classDumpClassFull] pr");
	if([pr count] > 0)
		[cls setObject:pr forKey:@"protocols"];
	else
		[cls setObject:@[] forKey:@"protocols"];

	//NSLog(@"[iSpy classDumpClassFull] className");
	[cls setObject:className 													 forKey:@"className"];
	//NSLog(@"[iSpy classDumpClassFull] superClassName");
	[cls setObject:[NSString stringWithUTF8String:superClassName]				 forKey:@"superClass"];
	
	//NSLog(@"[iSpy classDumpClassFull] methodList");
	if([methodList count] > 0)
		[cls setObject:methodList  forKey:@"methods"];
	else
		[cls setObject:@[] forKey:@"methods"];
	
	//NSLog(@"[iSpy classDumpClassFull] iVars");
	[cls setObject:[NSArray arrayWithArray:[self iVarsForClass:className]]       forKey:@"ivars"];
	
	//NSLog(@"[iSpy classDumpClassFull] properties");
	[cls setObject:[NSArray arrayWithArray:[self propertiesForClass:className]]  forKey:@"properties"];
	//[cls setObject:[NSArray arrayWithArray:[self protocolsForClass:className]]  forKey:@"protocols"];

	//NSLog(@"[iSpy classDumpClassFull] return");
	//return [cls copy];
	return cls;
}

// This function does the same thing, only for a single specified class name.
-(NSDictionary *)classDumpClass:(NSString *)className {
	static const char *none = "none";
	unsigned int numProtocols;
	NSMutableDictionary *cls = [[NSMutableDictionary alloc] init];
	if(!cls)
		return nil;

	Class theClass = objc_getClass([className UTF8String]);
	if(!theClass) 
		return nil;

	Class superClass = class_getSuperclass(theClass);
	char *superClassName = NULL;

	if(superClass)
		superClassName = (char *)class_getName(superClass);
	
	if(!superClassName)
		superClassName = (char *)none;

	Protocol **protocols = class_copyProtocolList(theClass, &numProtocols);
	NSMutableArray *pr = [[NSMutableArray alloc] init];
	if(numProtocols) {
		for(int i = 0; i < numProtocols; i++) {
			[pr addObject:[NSString stringWithUTF8String:protocol_getName(protocols[i])]];
		}
		free(protocols);
	}

	NSArray *methodList = [self methodListForClass:className];
	if(!methodList)
		methodList = @[];

	[cls setObject:pr forKey:@"protocols"];
	[cls setObject:className forKey:@"className"];
	[cls setObject:[NSString stringWithUTF8String:superClassName] forKey:@"superClass"];
	[cls setObject:methodList  forKey:@"methods"];
	[cls setObject:[NSArray arrayWithArray:[self iVarListForClass:className]] forKey:@"ivars"];
	[cls setObject:[NSArray arrayWithArray:[self propertyListForClass:className]] forKey:@"properties"];
	[cls setObject:[NSArray arrayWithArray:[self protocolListForClass:className]] forKey:@"protocols"];

	//return [cls copy];
	return cls;
}


/*
 *
 * Methods for working with protocols.
 *
 */

-(NSArray *)propertiesForProtocol:(Protocol *)protocol {
	unsigned int propertyCount = 0, j;
	objc_property_t *propertyList = protocol_copyPropertyList(protocol, &propertyCount);
	NSMutableArray *properties = [[NSMutableArray alloc] init];

	if(!propertyList)
		return properties;

	for(j = 0; j < propertyCount; j++) {
		NSMutableDictionary *property = [[NSMutableDictionary alloc] init];

		char *name = (char *)property_getName(propertyList[j]);
		char *attr = bf_get_attrs_from_signature((char *)property_getAttributes(propertyList[j])); 
		[property setObject:[NSString stringWithUTF8String:attr] forKey:[NSString stringWithUTF8String:name]];
		[properties addObject:property];
		free(attr);
	}
	//return [properties copy];
	return properties;
}

-(NSArray *)methodsForProtocol:(Protocol *)protocol {
	BOOL isReqVals[4] =      {NO, NO,  YES, YES};
	BOOL isInstanceVals[4] = {NO, YES, NO,  YES};
	unsigned int methodCount;
	NSMutableArray *methods = [[NSMutableArray alloc] init];

	for( int i = 0; i < 4; i++ ){
		struct objc_method_description *methodDescriptionList = protocol_copyMethodDescriptionList(protocol, isReqVals[i], isInstanceVals[i], &methodCount);
		if(!methodDescriptionList)
			continue;

		if(methodCount <= 0) {
			free(methodDescriptionList);
			continue;
		}

		NSMutableDictionary *methodInfo = [[NSMutableDictionary alloc] init];
		for(int j = 0; j < methodCount; j++) {
			NSArray *types = ParseTypeString([NSString stringWithUTF8String:methodDescriptionList[j].types]);
			[methodInfo setObject:[NSString stringWithUTF8String:sel_getName(methodDescriptionList[j].name)] forKey:@"methodName"];
			[methodInfo setObject:[types objectAtIndex:0] forKey:@"returnType"];
			[methodInfo setObject:((isReqVals[i]) ? @"1" : @"0") forKey:@"required"];
			[methodInfo setObject:((isInstanceVals[i]) ? @"1" : @"0") forKey:@"instance"];

			NSMutableArray *params = [[NSMutableArray alloc] init];
			if([types count] > 3) {  // return_type, class, selector, ...
				NSRange range;
				range.location = 3;
				range.length = [types count]-3;
				[params addObject:[types subarrayWithRange:range]];
			}
			[methodInfo setObject:params forKey:@"parameters"];
		}

		[methods addObject:methodInfo];

		free(methodDescriptionList);
	}
	//return [methods copy];
	return methods;
}


-(NSDictionary *)protocolDump {
	unsigned int protocolCount = 0, j;
	Protocol **protocols = objc_copyProtocolList(&protocolCount);
	NSMutableDictionary *protocolList = [[NSMutableDictionary alloc] init];

	if(protocolCount <= 0)
		return protocolList;

	// some of this code was inspired by (and a little of it is copy/pasta) https://gist.github.com/markd2/5961219
	for(j = 0; j < protocolCount; j++) {
		NSMutableArray *adoptees;
		NSMutableDictionary *protocolInfoDict = [[NSMutableDictionary alloc] init];
		const char *protocolName = protocol_getName(protocols[j]); 
		unsigned int adopteeCount;
		Protocol **adopteesList = protocol_copyProtocolList(protocols[j], &adopteeCount);

		if(!adopteeCount) {
			free(adopteesList);
			continue;
		}

		adoptees = [[NSMutableArray alloc] init];
		for(int i = 0; i < adopteeCount; i++) {
			const char *adopteeName = protocol_getName(adopteesList[i]);

			if(!adopteeName) {
				free(adopteesList);
				continue; // skip broken names or shit we don't care about
			}
			[adoptees addObject:[NSString stringWithUTF8String:adopteeName]];
		}
		free(adopteesList);

		[protocolInfoDict setObject:[NSString stringWithUTF8String:protocolName] forKey:@"protocolName"];
		[protocolInfoDict setObject:adoptees forKey:@"adoptees"];
		[protocolInfoDict setObject:[self propertiesForProtocol:protocols[j]] forKey:@"properties"];
		[protocolInfoDict setObject:[self methodsForProtocol:protocols[j]] forKey:@"methods"];

		[protocolList setObject:protocolInfoDict forKey:[NSString stringWithUTF8String:protocolName]];
	}
	free(protocols);
	//return (NSDictionary *)[protocolList copy];
	return (NSDictionary *)protocolList;
}

/*
    Return a dictionary, with one entry per network interface (en0, en1, lo0)
*/
-(NSDictionary *)getNetworkInfo {
    NSString *address;
    NSString *interface;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];

    success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            interface = [NSString stringWithUTF8String:temp_addr->ifa_name];
            address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
            [info setValue:address forKey:interface];
            temp_addr = temp_addr->ifa_next;
        }
    }

    freeifaddrs(interfaces);
    return info;
}

-(void *(*)(id, SEL, ...)) swizzleSelector:(SEL)originalSelector withFunction:(IMP)function forClass:(id)cls isInstanceMethod:(BOOL)isInstance {
	Class theClass;
	Method originalMethod;
	IMP originalImplementation;

	if(isInstance) {
		theClass = [cls class];	
		originalMethod = class_getInstanceMethod(theClass, originalSelector);
	}
	else {
		theClass = object_getClass(cls);
		originalMethod = class_getClassMethod(theClass, originalSelector);
	}
	originalImplementation = method_getImplementation(originalMethod);
	
    class_replaceMethod(theClass, originalSelector, function, method_getTypeEncoding(originalMethod));
    return (void *(*)(id, SEL, ...))originalImplementation;
}

-(void)sendToElasticsearch:(NSDictionary *)dict withService:(NSString *)svc {
	// Create the request.
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", ELASTICSEARCH_URL, svc]];
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
	request.HTTPMethod = @"POST";
	[request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[request addValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:kNilOptions error:&error];
	[request setHTTPBody:data];
	//NSLog(@"[bf_websocket_write] POSTING data: %@  //  %@", dictionary, data);

	if (!error) {
	    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
	        //NSLog(@"[bf_websocket_write] Completed POST. Data: %@  //  Response: %@  //  Error: %@", data, response, error);
	    }];
	   [dataTask resume];
	} 

	return;
}
@end


/***********************************************************************************************
 * These are public functions                                                                  *
 ***********************************************************************************************/

// The caller is responsible for calling free() on the pointer returned by this function.
char *bf_get_type_from_signature(char *typeStr) {
	//NSLog(@"[bf_get_type_from_signature] ParseTypeString");
	if(typeStr) {
		NSArray *types = ParseTypeString([NSString stringWithUTF8String:typeStr]);
		//NSLog(@"[bf_get_type_from_signature] done");

		if(types) {
			NSString *type = nil;

			if([types count] > 0) {
				//NSLog(@"[bf_get_type_from_signature] types: %@", types);
				type = [types objectAtIndex:0];
				if(type)
					return (char *)strdup([[types objectAtIndex:0] UTF8String]);	
			}
		} 
	}
	
	return strdup("__unknown__");
}


/***********************************************************************************************
 * These are private functions that aren't intended to be exposed to iSpy class and/or Cycript *
 ***********************************************************************************************/

static NSString *changeDateToDateString(NSDate *date) {
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	NSString *dateString = [dateFormatter stringFromDate:date];
	if(dateString == nil)
		return @"Bad date.";
	return dateString;
}

/*
	Returns the human-friendly return type for the method specified.
	Eg. "void" or "char *" or "id", etc.
	The caller must free() the buffer returned by this func.
*/
static char *bf_get_friendly_method_return_type(Method method) {
	// Here, I'll paste from the Apple docs:
	//      "The method's return type string is copied to dst. dst is filled as if strncpy(dst, parameter_type, dst_len) were called."
	// Um, ok... but how big does my destination buffer need to be?
	char tmpBuf[1024];

	// Does it pad with a NULL? Jeez. *shakes fist in Apple's general direction*
	memset(tmpBuf, 0, 1024);
	method_getReturnType(method, tmpBuf, 1023);
	return bf_get_type_from_signature(tmpBuf);
}

// based on code from https://gist.github.com/markd2/5961219
// The caller must free the returned pointer.
static char *bf_get_attrs_from_signature(char *attributeCString) {
	NSString *attributeString = @( attributeCString );
	NSArray *chunks = [attributeString componentsSeparatedByString: @","];
	NSMutableArray *translatedChunks = [NSMutableArray arrayWithCapacity: chunks.count];
	char *subChunk, *type;

	NSString *string;

	for (NSString *chunk in chunks) {
		unichar first = [chunk characterAtIndex: 0];

		switch (first) {
			case 'T': // encode type. @ has class name after it
				subChunk = (char *)[[chunk substringFromIndex: 1] UTF8String];
				type = bf_get_type_from_signature(subChunk);
				break;
			case 'V': // backing ivar name
				//string = [NSString stringWithFormat: @"ivar: %@", [chunk substringFromIndex: 1]];
				//[translatedChunks addObject: string];
				break;
			case 'R': // read-only
				[translatedChunks addObject: @"readonly"];
				break;
			case 'C': // copy
				[translatedChunks addObject: @"copy"];
				break;
			case '&': // retain
				[translatedChunks addObject: @"retain"];
				break;
			case 'N': // non-atomic
				[translatedChunks addObject: @"non-atomic"];
				break;
			case 'G': // custom getter
				string = [NSString stringWithFormat: @"getter: %@",[chunk substringFromIndex: 1]];
				[translatedChunks addObject: string];
				break;
			case 'S': // custom setter
				string = [NSString stringWithFormat: @"setter: %@", [chunk substringFromIndex: 1]];
				[translatedChunks addObject: string];
				break;
			case 'D': // dynamic
				[translatedChunks addObject: @"dynamic"];
				break;
			case 'W': // weak
				[translatedChunks addObject: @"__weak"];
				break;
			case 'P': // eligible for GC
				[translatedChunks addObject: @"GC"];
				break;
			case 't': // old-style encoding
				[translatedChunks addObject: chunk];
				break;
			default:
				[translatedChunks addObject: chunk];
				break;
		}
	}
	//NSString *result = [NSString stringWithFormat:@"(%@) %s", [translatedChunks componentsJoinedByString: @", "], type];
	NSString *result = [NSString stringWithFormat:@"%@", [translatedChunks componentsJoinedByString: @", "]];

	return strdup([result UTF8String]);
}

EXPORT NSString *base64forData(NSData *theData) {
	const uint8_t* input = (const uint8_t*)[theData bytes];
	NSInteger length = [theData length];

	static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

	NSMutableData* data = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
	uint8_t* output = (uint8_t*)data.mutableBytes;

	NSInteger i;
	for (i=0; i < length; i += 3) {
		NSInteger value = 0;
		NSInteger j;
		for (j = i; j < (i + 3); j++) {
			value <<= 8;

			if (j < length) {
				value |= (0xFF & input[j]);
			}
		}

		NSInteger theIndex = (i / 3) * 4;
		output[theIndex + 0] =                    table[(value >> 18) & 0x3F];
		output[theIndex + 1] =                    table[(value >> 12) & 0x3F];
		output[theIndex + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
		output[theIndex + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
	}

	return [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
}

NSString *SHA256HMAC(NSData *theData) {
    const char *cKey  = (const char *)"This is a hardcoded but unimportant key. Don't do this at home.";
    unsigned char *cData = (unsigned char *)[theData bytes];
    unsigned char cHMAC[CC_SHA256_DIGEST_LENGTH+1];

    if(!cData) {
    	NSLog(@"[iSpy] Error with theData in SHA256HMAC");
    	return nil;
    }
    memset(cHMAC, 0, sizeof(cHMAC));
    CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), cData, [theData length], cHMAC);

    NSMutableString *result = [[NSMutableString alloc] init];
    for (int i = 0; i < sizeof(cHMAC); i++) {
        [result appendFormat:@"%02hhx", cHMAC[i]];
    }

    //return [result copy];
    return result;
}
