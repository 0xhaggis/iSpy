#include <pthread.h>
#include <dlfcn.h>
#include "3rd-party/fishhook/fishhook.h"
#include "iSpy.common.h"
#include "iSpy.class.h"
#include "iSpy.instance.h"
#include "iSpy.msgSend.watchlist.h"
#include "iSpy.msgSend.h"

id (*orig_NSAllocateObject)(Class cls, NSUInteger extraBytes, NSZone *zone);
id (*orig_objc_constructInstance)(Class cls, void *bytes);
id (*orig_objc_destructInstance)(id obj);
id (*orig_alloc)(Class cls, SEL selector);
id (*orig_dealloc)(id obj, SEL selector);

static char *appName = NULL;
static iSpy *mySpy;

@implementation InstanceTracker

+(InstanceTracker *) sharedInstance {
	static InstanceTracker *sharedInstance;
	static dispatch_once_t once;
	static InstanceMap_t instanceMap;

	dispatch_once(&once, ^{
		sharedInstance = [[self alloc] init];
		[sharedInstance setEnabled:false];
		// XXX FIXME [sharedInstance installHooks];
		[sharedInstance setInstanceMap:&instanceMap];
	});

	return sharedInstance;
}

-(void) installHooks {
	ispy_log("Hooking Objective-C class create/dispose functions...");
	
	/*
	orig_objc_constructInstance = (id(*)(Class, void *))dlsym(RTLD_DEFAULT, "objc_constructInstance");
	rebind_symbols((struct rebinding[1]){{(char *)"objc_constructInstance", (void *)bf_objc_constructInstance}}, 1); 

	orig_NSAllocateObject = (id(*)(Class, NSUInteger, NSZone *))dlsym(RTLD_DEFAULT, "NSAllocateObject");
	rebind_symbols((struct rebinding[1]){{(char *)"NSAllocateObject", (void *)bf_NSAllocateObject}}, 1); 
	*/

	//orig_objc_destructInstance = (id(*)(id))dlsym(RTLD_DEFAULT, "objc_destructInstance");
	//rebind_symbols((struct rebinding[1]){{(char *)"objc_destructInstance", (void *)bf_objc_destructInstance}}, 1); 

	// force this to cache its stuff for speed
	
	appName = (char *) [[[NSProcessInfo processInfo] arguments][0] UTF8String];	

	[self stop]; // force this to be safe

	orig_alloc = (id(*)(Class,SEL))[[iSpy sharedInstance] swizzleSelector:@selector(alloc)
		withFunction:(IMP)bf_alloc
		forClass:(id)objc_getClass("NSObject")
		isInstanceMethod:FALSE];

	orig_dealloc = (id(*)(id,SEL))[[iSpy sharedInstance] swizzleSelector:@selector(dealloc)
		withFunction:(IMP)bf_dealloc
		forClass:(id)objc_getClass("NSObject")
		isInstanceMethod:TRUE];
	
	mySpy = [iSpy sharedInstance];

	ispy_log("Done. Ready to be started.");
}

-(void) start {
	[self clear];
	[self setEnabled:true];
}

-(void) stop {
	[self setEnabled:false];
}

-(void) clear {
	InstanceMap_t *instanceMap = [self instanceMap];
	(*instanceMap).clear();
}

-(NSArray *) instancesOfAllClasses {
	InstanceMap_t *instanceMap = [self instanceMap];
	if(!instanceMap)
		return @[];

	NSMutableArray *instances = [[NSMutableArray alloc] init];

	for(InstanceMap_t::const_iterator it = (*instanceMap).begin(); it != (*instanceMap).end(); ++it) {
		if(!it->first)
			break;
		[instances addObject:[NSString stringWithFormat:@"0x%x", it->first]];
	}

	return (NSArray *)instances;
}

-(NSArray *) instancesOfAppClasses {
	NSLog(@"[instance] entering instancesOfAppClasses");
	InstanceMap_t *instanceMap = [self instanceMap];
	if(!instanceMap)
		return @[];

	NSMutableArray *instances = [[NSMutableArray alloc] init];

	NSLog(@"[instance] Loop");
	for(InstanceMap_t::const_iterator it = (*instanceMap).begin(); it != (*instanceMap).end(); ++it) {
		NSLog(@"[instance] first");
		id obj = (id)(unsigned long)it->first;
		if(!obj)
			continue;

		if(!is_valid_pointer(obj))
			continue;

		NSLog(@"[instance] obj = %lx", (unsigned long)obj);

		NSLog(@"[instance] object_getClass");
		Class c = object_getClass(obj);
		if(!is_valid_pointer(c))
			continue;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations" // this is so we can dereference ->isa

		if(!(is_valid_pointer(((struct objc_object *)(c))->isa)))
			continue;
		
		if(!(is_valid_pointer(((struct objc_object *)(obj))->isa)))
			continue;

		if(((struct objc_object *)(obj))->isa != c)
			continue;

		@try {
			if(![obj respondsToSelector:@selector(class)])
				continue;
		} @catch(NSException *exception) {
			NSLog(@"[instance] EXCEPTION! %@", exception);
			continue;
		}

#pragma clang diagnostic push

		NSLog(@"[instance] class: %@", c);
		
		const char *className = ".broken.";
		
		NSLog(@"[instance] object_getClassName");
		className = class_getName(c);	
	
		if(!className)
			continue;

		NSLog(@"[instance] isClassFromApp");
		if(false == [iSpy isClassFromApp:[NSString stringWithUTF8String:className]])
			continue;

		NSLog(@"[instance] dict stuff");
		NSMutableDictionary *instanceData = [[NSMutableDictionary alloc] init];
		[instanceData setObject:[NSString stringWithFormat:@"%p", obj] forKey:@"address"];
		[instanceData setObject:[NSString stringWithUTF8String:className] forKey:@"class"];
		[instances addObject:(NSDictionary *)instanceData];
	}
	NSLog(@"[instance] returning instances");
	return [NSArray arrayWithArray:instances];
}

// Given a hex address (eg. 0xdeafbeef) dumps the class data from the object at that address.
// Returns an object as discussed in instance_dumpInstance, below.
// This is exposed to /api/instance/0xdeadbeef << replace deadbeef with an actual address.
-(id)instanceAtAddress:(NSString *)addr {
	return [self __dumpInstance:[self __instanceAtAddress:addr]];
}

// Given a string in the format @"0xdeadbeef", this first converts the string to an address, then
// returns an opaque Objective-C object at that address.
// The runtime can treat this return value just like any other object.
// BEWARE: give this an incorrect/invalid address and you'll return a duff pointer. Caveat emptor.
-(id)__instanceAtAddress:(NSString *)addr {
	return (id)strtoul([addr UTF8String], (char **)NULL, 16);
}

// Pass an object pointer to this method.
// In return it'll give you an array. Each element in the array represents an iVar.
// Each iVar entry is a dictionary that represents the name, type, and value of the iVar.
-(NSArray *)__dumpInstance:(id)instance {
	//ispy_log("[__dumpInstance] Calling [iSpy sharedInstance]");

	NSMutableArray *iVarData = [[NSMutableArray alloc] init];

	// Make sure that the requested instance is still a valid object
	InstanceMap_t *instanceMap = [self instanceMap];
	if((*instanceMap)[(unsigned long)instance] != (unsigned long)instance)
		return @[@"Error, object has been destroyed"];

	const char *className = object_getClassName(instance);
	if(!className)
		return @[@"Error, the class name could not be found"];

	NSString *NSClassName = [NSString stringWithUTF8String:className];
	NSArray *instanceIVars = [[iSpy sharedInstance] iVarsForClass:NSClassName];
	if(!instanceIVars)
		return @[@"Error, iVars could not be found for the object"];

	// Loop through each of the iVars in this instance's Class
	for(int i=0; i< [instanceIVars count]; i++) {
		//NSLog(@"Looping %d", i);
		// Each iVar is described by the attributes:
		//	name
		//	type
		//	typeEncoding
		//	value
		NSMutableDictionary *iVar = [[instanceIVars objectAtIndex:i] mutableCopy];
		NSString *iVarTypeEncoding = [iVar objectForKey:@"typeEncoding"];
		NSString *iVarName = [iVar objectForKey:@"name"];
		//NSString *iVarType = [iVar objectForKey:@"type"];
		//NSLog(@"name: %@ // type: %@ // encoding: %@", iVarName, iVarType, iVarTypeEncoding);
		const char *iVarTypeStr = [iVarTypeEncoding UTF8String];
		BOOL isPointer = FALSE;

		if(*iVarTypeStr == '^') {
            isPointer = TRUE;
            iVarTypeStr++;
        }

        //NSLog(@"Get iVarPtr...");
        void *iVarPtr;
        object_getInstanceVariable(instance, [iVarName UTF8String], &iVarPtr);

        //NSLog(@"Switch on iVarPtr...");
        NSString *iVarValue;
	    
	    // lololol
	    unsigned long v = (unsigned long)iVarPtr;
	    double d = (double)v;
		
		switch(*iVarTypeStr) {
	        case 'c': // char
	        case 'C': // unsigned char
	            iVarValue = [NSString stringWithFormat:@"0x%02lx", (unsigned long)(iVarPtr)&0xff];
	            break;

	        case 'i': // int
	        case 's': // short
	            iVarValue = [NSString stringWithFormat:@"0x%lx (%ld)", (long)iVarPtr, (long)iVarPtr];
	            break;

	        case 'l': // long
				iVarValue = [NSString stringWithFormat:@"0x%lx (%ld)", (unsigned long)iVarPtr, (long)iVarPtr];	            
	            break;

	        case 'q': // long long
				iVarValue = [NSString stringWithFormat:@"0x%llx (%lld)", (unsigned long long)iVarPtr, (long long)iVarPtr];	            	            
	            break;

	        case 'I': // unsigned int
	        case 'S': // unsigned short
	            iVarValue = [NSString stringWithFormat:@"0x%lx (%lu)", (unsigned long)iVarPtr, (unsigned long)iVarPtr];
	            break;

	        case 'L': // unsigned long
	            iVarValue = [NSString stringWithFormat:@"0x%lx (%lu)", (unsigned long)iVarPtr, (unsigned long)iVarPtr];	            
	            break;

	        case 'Q': // unsigned long long
	            iVarValue = [NSString stringWithFormat:@"0x%llx (%llu)", (unsigned long long)iVarPtr, (unsigned long long)iVarPtr];	            
	            break;

	        case 'f': // float
	        	iVarValue = [NSString stringWithFormat:@"%f", (float)d];	            
	        	break;

	        case 'd': // double  
	            iVarValue = [NSString stringWithFormat:@"%f", (double)d];	            
	            break;

	        case 'B': // BOOL
	            iVarValue = [NSString stringWithFormat:@"%ld", (unsigned long)iVarPtr&0xff];
	            break;

	        case 'v': // void
	        	if(isPointer)
	            	iVarValue = [NSString stringWithFormat:@"%p", iVarPtr];
	            else
	            	iVarValue = @"WTF";
	            break;

	        case '*': // char *
	            iVarValue = [NSString stringWithFormat:@"%p", iVarPtr];
	            break;

	        case '{': // struct
	            iVarValue = [NSString stringWithFormat:@"%p", iVarPtr];
	            break;

	        case ':': // selector
	            iVarValue = [NSString stringWithFormat:@"%s", sel_getName((SEL)iVarPtr)];
	            break;

	        case '?': // usually a function pointer
	            iVarValue = [NSString stringWithFormat:@"%p", iVarPtr];
	            break;

	        case '@': // object
	            if(isPointer) {
	                iVarValue = [NSString stringWithFormat:@"%p", iVarPtr];
	            } else {
	            	iVarValue = [NSString stringWithFormat:@"%@", (id)iVarPtr];
	            }
	            break;

	        case '#': // class
				iVarValue = [NSString stringWithFormat:@"Class: %s", class_getName((Class)iVarPtr)];
				break;
	        
	        default:
	            iVarValue = [NSString stringWithFormat:@"Unknown type encoding: %@", iVarTypeEncoding];
	            break;     
    	}

    	//NSLog(@"[dump instance] iVarValue: %@", iVarValue);
        [iVar setObject:iVarValue forKey:@"value"];
        [iVarData addObject:iVar];
    }

    //return (NSArray *)[iVarData copy];
    return (NSArray *)iVarData;
}
@end

/*
 * Private methods used to hook the Objective-C runtime create/destroy functions
 */

id bf_alloc(Class cls, SEL selector) {
	char part1[] = "{\"messageType\":\"addObject\",\"messageData\":{\"class\":\"";
	char part2[] = "\",\"address\":\"";
	char part3[] = "\",\"method\":\"alloc\"}}";
	char *buf, *className;
	int len;

	if(!cls || !selector)
		return orig_alloc(cls, selector);

	InstanceTracker *tracker = [InstanceTracker sharedInstance];
	if(!tracker || !tracker.enabled) {
		return orig_alloc(cls, selector);
	}

	className = (char *)class_getName(cls);
	if(!className || !watchlist_is_class_on_watchlist(className)) {
		return orig_alloc(cls, selector);
	}

	id newObject = orig_alloc(cls, selector);
		
	if(newObject) {
		//len = strlen(part1) + strlen(part2) + strlen(part3) + 20 + strlen(className) + 1;
		buf = (char *)malloc(16000);
		if(buf) {
			snprintf(buf, 15999, "%s%s%s%p%s", part1, className, part2, newObject, part3);
			bf_websocket_write(buf);
			free(buf);
		}

		InstanceMap_t *instanceMap = tracker.instanceMap;
		if(instanceMap)
			(*instanceMap)[(unsigned long)newObject] = (unsigned long)newObject;
	}

	return newObject;
}

id bf_dealloc(id obj, SEL selector) {
	char part1[] = "{\"messageType\":\"removeObject\",\"messageData\":{\"class\":\"";
	char part2[] = "\",\"address\":\"";
	char part3[] = "\",\"method\":\"dealloc\"}}";
	char *buf, *className;
	int len;

	if(!obj)
		return orig_dealloc(obj, selector);

	InstanceTracker *tracker = [InstanceTracker sharedInstance];
	if(!tracker || !tracker.enabled) {
		return orig_dealloc(obj, selector);
	}

	className = (char *)object_getClassName(obj);
	if(!className || !watchlist_is_class_on_watchlist(className)) {
		return orig_dealloc(obj, selector);
	}

	//NSLog(@"[iSpy] Releasing %p", obj);
	//len = strlen(part1) + strlen(part2) + strlen(part3) + 20 + strlen(className) + 1;
	buf = (char *)malloc(16000);
	if(buf) {
		snprintf(buf, 15999, "%s%s%s%p%s", part1, className, part2, obj, part3);
		bf_websocket_write(buf);
		free(buf);
	}
		
	InstanceMap_t *instanceMap = tracker.instanceMap;
	if(instanceMap)
		(*instanceMap).erase((unsigned long)obj);

	//NSLog(@"[iSpy] Calling orig %p", obj);
	id foo = orig_dealloc(obj, selector);
	//NSLog(@"[iSpy] Returning %p", foo);
	return foo;
}

id bf_NSAllocateObject(Class cls, NSUInteger extraBytes, NSZone *zone) {
 	id newObject = orig_NSAllocateObject(cls, extraBytes, zone);
	if(cls) {
		const char *className = class_getName(cls);
		if(className) {
			NSString *msg = [NSString stringWithFormat:@"{\"messageType\":\"addObject\",\"messageData\":{\"class\":\"%s\",\"address\":\"%p\",\"method\":\"NSAllocateObject\"}}", className, newObject];
			if(msg)
				bf_websocket_write([msg UTF8String]);
		}
	}	
 	return newObject;
}

