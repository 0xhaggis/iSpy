#include <sys/types.h>
#include <ctype.h>
#import <string>
#include <dirent.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <mach-o/dyld.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <stdarg.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFStream.h>
#import <CFNetwork/CFNetwork.h>
#include <pthread.h>
#include <CFNetwork/CFProxySupport.h>
#import <Security/Security.h>
#include <Security/SecCertificate.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <objc/objc.h>
#include "iSpy.common.h"
#include "iSpy.class.h"
#include "iSpy.msgSend.watchlist.h"
#include <stack>
#include <pthread.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <objc/runtime.h>
#include "iSpy.msgSend.h"
#include "3rd-party/fishhook/fishhook.h"


//
// In this file, all the __log__() functions are #ifdef'd out unless you add:
//      #define DO_SUPER_DEBUG_MODE 1
// to iSpy.msgSend.h. Don't do this unless you're debugging iSpy itself - it's super slow.
//

// hard-coded for now while we're 32-bit only.
#define PAGE_SIZE 4096
#define MALLOC_BUFFER_SIZE PAGE_SIZE * 256 // ~ 1MB
#define MINIBUF_SIZE 256

static unsigned int msgCount = 0;

// These are the classes we know to be stable when send the "description" selector.
// It's not a definitive list!
static NSArray *loggableClasses = @[
    @"NSString", @"NSArray", @"NSDictionary", @"NSURL", @"NSNumber", 
    @"NSData", @"NSDate", @"NSTextField", @"NSFileHandle", @"NSURLCache",
    @"NSBundle", @"NSURLSession", @"NSURLRequest", @"NSMutableData", 
    @"NSMUtableArray", @"NSURLHangle", @"NSURLConnection", @"NSURLCredential",
    @"NSURLProtectionSpace", @"NSURLResponse",
    @"NSConcreteMutableData", @"__NSArrayI", @"__NSCFConstantString", @"__NSDictionaryI",
    @"__NSCFNumber", @"__NSCFNumber", @"__NSCFString", @"__NSDictionaryM", @"__NSArrayM",
    @"NSFileManager", @"NSUserDefaults", @"__NSDate", @"NSPathStore2"
];

pthread_once_t key_once = PTHREAD_ONCE_INIT;
pthread_key_t stack_keys[128], curr_stack_key;

id (*orig_objc_msgSend)(id theReceiver, SEL theSelector, ...) __asm__("_orig_objc_msgSend");
static id (*orig_objc_msgSend_local)(id theReceiver, SEL theSelector, ...) __asm__("_orig_objc_msgSend_local");
__attribute((weakref("replaced_objc_msgSend"))) static void replaced_objc_msgSend() __asm__("_replaced_objc_msgSend");
void (*orig_objc_msgSend_stret)(void *stretAddr, id theReceiver, SEL theSelector, ...);
static iSpy *msgSpy = NULL;

static void (*orig_test_print_args)(id theReceiver, SEL theSelector, ...) __asm__("_orig_test_print_args");
void test_print_args(id obj, SEL sel) __asm__ ("_test_print_args");
void test_print_args(id obj, SEL sel) {
    NSLog(@"OIOIOIOI obj: %s  //  sel: %s", object_getClassName(obj), sel_getName(sel));
}

extern "C" USED inline void increment_depth() {
    long currentDepth = (long)pthread_getspecific(curr_stack_key);
    currentDepth++;
    pthread_setspecific(curr_stack_key, (void *)currentDepth);
}

extern "C" USED inline void decrement_depth() {
    long currentDepth = (long)pthread_getspecific(curr_stack_key);
    currentDepth--;
    pthread_setspecific(curr_stack_key, (void *)currentDepth);
}

extern "C" USED inline long get_depth() {
    return (long)pthread_getspecific(curr_stack_key);
}

extern "C" USED inline void *saveBuffer(void *buffer) {
    increment_depth();
    pthread_setspecific(stack_keys[get_depth()], buffer);
    return buffer;
}

extern "C" USED inline void *loadBuffer() {
    void *buffer;
    buffer = pthread_getspecific(stack_keys[get_depth()]);
    return buffer;
}

extern "C" USED inline void cleanUp() {
    //__log__("cleanUp");
    void *buf = pthread_getspecific(stack_keys[get_depth()]);
    free((void *)buf);
    decrement_depth();
}

extern "C" void bf_setup_msgSend_stack() {
    // setup pthreads
    pthread_key_create(&curr_stack_key, NULL);
    pthread_setspecific(curr_stack_key, 0);
    for(int i = 0; i < 128; i++) { // this is stupid and will go boom if we get > 128 nested or recursive ObjC calls
        pthread_key_create(&(stack_keys[i]), NULL);
        pthread_setspecific(stack_keys[i], 0);
    }
}

// pushes 256 bytes of registers onto the stack @ SP
#define PUSH_REGS \
    "sub sp, sp, #256\n" \
    "stp x0, x1, [sp, #0]\n" \
    "stp x2, x3, [sp, #16]\n" \
    "stp x4, x5, [sp, #32]\n" \
    "stp x6, x7, [sp, #48]\n" \
    "stp x8, x9, [sp, #64]\n" \
    "stp x10, x11, [sp, #80]\n" \
    "stp x12, x13, [sp, #96]\n" \
    "stp x14, x15, [sp, #112]\n" \
    "stp x16, x17, [sp, #128]\n" \
    "stp x18, x19, [sp, #144]\n" \
    "stp x20, x21, [sp, #160]\n" \
    "stp x22, x23, [sp, #176]\n" \
    "stp x24, x25, [sp, #192]\n" \
    "stp x26, x27, [sp, #208]\n" \
    "stp x28, x29, [sp, #224]\n" \
    "stp x30, fp, [sp, #240]\n"

#define POP_REGS \
    "ldp x0, x1, [sp, #0]\n" \
    "ldp x2, x3, [sp, #16]\n" \
    "ldp x4, x5, [sp, #32]\n" \
    "ldp x6, x7, [sp, #48]\n" \
    "ldp x8, x9, [sp, #64]\n" \
    "ldp x10, x11, [sp, #80]\n" \
    "ldp x12, x13, [sp, #96]\n" \
    "ldp x14, x15, [sp, #112]\n" \
    "ldp x16, x17, [sp, #128]\n" \
    "ldp x18, x19, [sp, #144]\n" \
    "ldp x20, x21, [sp, #160]\n" \
    "ldp x22, x23, [sp, #176]\n" \
    "ldp x24, x25, [sp, #192]\n" \
    "ldp x26, x27, [sp, #208]\n" \
    "ldp x28, x29, [sp, #224]\n" \
    "ldp x30, fp, [sp, #240]\n" \
    "add sp, sp, #256\n"

#define RESTORE_FROM_MALLOC \
    "bl _loadBuffer\n" \
    "sub sp, sp, #16\n" \
    "ldp x2, x3, [x0, #0]\n" \
    "stp x2, x3, [sp, #0]\n" \
    "ldp x2, x3, [x0, #16]\n" \
    "ldp x4, x5, [x0, #32]\n" \
    "ldp x6, x7, [x0, #48]\n" \
    "ldp x8, x9, [x0, #64]\n" \
    "ldp x10, x11, [x0, #80]\n" \
    "ldp x12, x13, [x0, #96]\n" \
    "ldp x14, x15, [x0, #112]\n" \
    "ldp x16, x17, [x0, #128]\n" \
    "ldp x18, x19, [x0, #144]\n" \
    "ldp x20, x21, [x0, #160]\n" \
    "ldp x22, x23, [x0, #176]\n" \
    "ldp x24, x25, [x0, #192]\n" \
    "ldp x26, x27, [x0, #208]\n" \
    "ldp x28, x29, [x0, #224]\n" \
    "ldp x30, fp, [x0, #240]\n" \
    "ldp x0, x1, [sp, #0]\n" \
    "add sp, sp, #16\n"
    
__asm__  (
    "_replaced_objc_msgSend:\n"

    // PUSH the regs to the stack (sp -= 256)
    PUSH_REGS

    // allocate a 256 byte buffer and save a copy of its address
    "mov x0, #256\n"
    "bl _malloc\n"
    "bl _saveBuffer\n"
    
    // now save rest of regs (except x0,x1) in malloc buf
    "ldp x2, x3, [sp, #0]\n" // use x2, x3 instead of x0, x1 for this load/store cycle
    "stp x2, x3, [x0, #0]\n" // use x2, x3 instead of x0, x1 for this load/store cycle
    "ldp x2, x3, [sp, #16]\n"
    "stp x2, x3, [x0, #16]\n"
    "ldp x4, x5, [sp, #32]\n"
    "stp x4, x5, [x0, #32]\n"
    "ldp x6, x7, [sp, #48]\n"
    "stp x6, x7, [x0, #48]\n"
    "ldp x8, x9, [sp, #64]\n"
    "stp x8, x9, [x0, #64]\n"         
    "ldp x10, x11, [sp, #80]\n"
    "stp x10, x11, [x0, #80]\n"
    "ldp x12, x13, [sp, #96]\n"
    "stp x12, x13, [x0, #96]\n"
    "ldp x14, x15, [sp, #112]\n"
    "stp x14, x15, [x0, #112]\n"
    "ldp x16, x17, [sp, #128]\n"
    "stp x16, x17, [x0, #128]\n"
    "ldp x18, x19, [sp, #144]\n"
    "stp x18, x19, [x0, #144]\n"
    "ldp x20, x21, [sp, #160]\n"
    "stp x20, x21, [x0, #160]\n"
    "ldp x22, x23, [sp, #176]\n"
    "stp x22, x23, [x0, #176]\n"
    "ldp x24, x25, [sp, #192]\n"
    "stp x24, x25, [x0, #192]\n"
    "ldp x26, x27, [sp, #208]\n"
    "stp x26, x27, [x0, #208]\n"
    "ldp x28, x29, [sp, #224]\n"
    "stp x28, x29, [x0, #224]\n"
    "ldp x30, fp, [sp, #240]\n"
    "stp x30, fp, [x0, #240]\n"
    
    // restore everything to normal
    POP_REGS

    // log this call
    "bl _parse_args\n"

    // restore everything so we can call the real objc_msgSend

    // get the malloc'd buffer into x0
    RESTORE_FROM_MALLOC

    // Call orig_objc_msgSend
    "adrp x19, _orig_objc_msgSend_local@PAGE\n"
    "ldr x19, [x19, _orig_objc_msgSend_local@PAGEOFF]\n"
    "blr x19\n"

    // save the returned registers
    PUSH_REGS

    // get the malloc'd buffer into x0
    "bl _loadBuffer\n"

    // restore the non-return registers from the buffer
    "ldp x8, x9, [x0, #64]\n"
    "ldp x10, x11, [x0, #80]\n"
    "ldp x12, x13, [x0, #96]\n"
    "ldp x14, x15, [x0, #112]\n"
    "ldp x16, x17, [x0, #128]\n"
    "ldp x18, x19, [x0, #144]\n"
    "ldp x20, x21, [x0, #160]\n"
    "ldp x22, x23, [x0, #176]\n"
    "ldp x24, x25, [x0, #192]\n"
    "ldp x26, x27, [x0, #208]\n"
    "ldp x28, x29, [x0, #224]\n"
    "ldp x30, fp, [x0, #240]\n"

    // restore the return registers
    "ldp x0, x1, [sp, #0]\n"
    "ldp x2, x3, [sp, #16]\n"
    "ldp x4, x5, [sp, #32]\n"
    "ldp x6, x7, [sp, #48]\n"

    // return the stack pointer to its rightful place
    "add sp, sp, #256\n"

    // at this point, the regs are good to return to the caller. Tidy up.
    PUSH_REGS

    // restore the registers 
    "bl _cleanUp\n"
    POP_REGS
    "br x30\n"
);

/*
extern "C" USED inline void *print_args(id self, SEL _cmd, ...) {
    void *retVal;
    std::va_list va;
    va_start(va, _cmd);
    retVal = print_args_v(self, _cmd, va);
    va_end(va);
    return retVal;
}
*/

// We're only interested in logging objc_msgSend calls if the class/selector are on our watchlist.
// Anything else gets passed straight to orig_objc_msgSend() without interference.
// This prevents us logging anything in the Apple Frameworks (by default; can still be added with watchlist_add_class(...))
extern "C" USED unsigned int is_this_method_on_watchlist(id Cls, SEL selector) {
    if(Cls && selector && msgSpy) {
        const char *name = sel_getName(selector);
        if(!name)
            return NO;

        if(strcmp(name, "description") == 0)
            return NO;

        char *classNameStr = (char *)object_getClassName(Cls);

        // Lookup the class. If it's not there, return FALSE.
        ClassMap_t *ClassMap = msgSpy->_classWhitelist;
        std::string className((const char *)classNameStr);
        ClassMap_t::iterator c_it = (*ClassMap).find(className);
        if(c_it == (*ClassMap).end()) {
            return NO;
        }

        // If it's there but there are no methods being tracked, that's weird. We return FALSE.
        MethodMap_t methods = c_it->second;
        if(methods.empty()) {
            return NO;
        }

        // Now we look up the method. If it doesn't exist, return FALSE.
        char *methodNameStr = (char *)sel_getName(selector);
        std::string methodName((const char *)methodNameStr);
        MethodMap_t::iterator m_it = methods.find(methodName);
        if(m_it == methods.end()) {
            return NO;
        }

        // Sweet. This [class method] is on the watchlist. Return the watchlistPtr.
        //__log__("[is_this_method_on_watchlist] Found [%s %s], logging it.", classNameStr, methodNameStr);
        return m_it->second;
    }
    else
        return NO;
}

EXPORT void bf_enable_msgSend() {
    if(msgSpy)
        msgSpy->msgSendLoggingEnabled = 1;
    ispy_log("[bf_enable_msgSend] Enabled msgSend!");
}

EXPORT void bf_disable_msgSend() {
    if(msgSpy)
        msgSpy->msgSendLoggingEnabled = 0;
    ispy_log("[bf_enable_msgSend] Disabled msgSend!");
}

EXPORT int bf_get_msgSend_state() {
    return msgSpy->msgSendLoggingEnabled;
}

// This is called in the main iSpy constructor. It hooks objc_msgSend and _stret.
EXPORT void bf_hook_msgSend() {
    int pagesize = sysconf(_SC_PAGE_SIZE);
    ispy_log("[hook_msgSend] Page size: %ld // align: %ld", pagesize, (long)objc_msgSend % pagesize);

    // msgSpy is static on the BSS, scoped to this file only.
    ispy_log("[hook_msgSend] Calling sharedInstance");
    msgSpy = [iSpy sharedInstance];
    ispy_log("[hook_msgSend] msgSpy is @ %p", msgSpy);

    ispy_log("[hook_msgSend] Ensuring logging is disabled...");
    bf_disable_msgSend();

    // setup the stack emulator
    pthread_once(&key_once, bf_setup_msgSend_stack);

    ispy_log("[hook_msgSend] Saving objc_msgSend* function pointers");
    // Save a function pointer to the real objc_msgSend() function
    orig_objc_msgSend = orig_objc_msgSend_local = (id(*)(id, SEL, ...))dlsym(RTLD_DEFAULT, "objc_msgSend");
    //orig_test_print_args = (void(*)(id, SEL, ...))dlsym(RTLD_DEFAULT, "test_print_args");
    //orig_objc_msgSend_stret = (void(*)(void *, id, SEL, ...))dlsym(RTLD_DEFAULT, "objc_msgSend_stret");
    NSLog(@"real: %p", (void *)dlsym(RTLD_DEFAULT, "objc_msgSend"));
    NSLog(@"orig: %p", (void *)orig_objc_msgSend);


    // Hook the objc_msgSend function and replace it with our own
    // XXX FIXME rebind_symbols((struct rebinding[1]){{(char *)"objc_msgSend", (void *)replaced_objc_msgSend}}, 1);
//    rebind_symbols((struct rebinding[1]){{(char *)"objc_msgSend_stret", (void *)replaced_objc_msgSend_stret}}, 1);

    // Do the same for _stret version of objc_msgSend. We should add _fpret and _super, too.
    //bf_hook_msgSend_stret();
    //ispy_log("[hook_msgSend] Hooks installed");
    ispy_log("[hook_msgSend] All done, returning to caller."); 
}

// Sometimes we NEED to know if a pointer is mapped into addressible space, otherwise we
// may dereference something that's a pointer to unmapped space, which will go boom.
// This uses mincore(2) to ask the XNU kernel if a pointer is within an app-mapped page.
extern "C" inline int is_valid_pointer(void *ptr) {
    char vec;
    int ret;
    static int pageSize = 0;

    if(!ptr)
        return NO; // dereferencing *ptr will go boom

    if(!pageSize)
        pageSize = getpagesize();

    ret = mincore(ptr, pageSize, &vec);
    if(ret == 0)
        if((vec & 1) == 1)
            return YES; // *ptr can be dereferenced safely

    return NO; // dereferencing *ptr will go boom
}

extern "C" USED inline void parse_returnValue(void *returnValue, struct objc_callState *callState) {
    __log__("[parse_returnValue] Entry");

    // if this method returns a non-void, we report it
    if(callState->returnType && callState->returnType[0] != 'v' && msgSpy->msgSendLoggingEnabled) {
        __log__("[parse_returnValue] Building JSON buffer that contains logged return value");
        char *returnValueJSON = parameter_to_JSON(callState->returnType, returnValue);
        snprintf(callState->json, MALLOC_BUFFER_SIZE, "%s},\"returnValue\":{%s,\"objectAddr\":\"%p\"},\"count\":%d}\n", 
            callState->json,
            returnValueJSON, 
            returnValue,
            msgCount
        );
        free(returnValueJSON);
    } 
    // In case we want to handle audit events differently
    else if(!msgSpy->msgSendLoggingEnabled) {
        __log__("[parse_returnValue] Just auditing, not logging.");
        snprintf(callState->json, MALLOC_BUFFER_SIZE, "%s},\"count\":%d}\n", callState->json, msgCount);        
    }
    // otherwise we don't bother.
    else {
        __log__("[parse_returnValue] No return value, not adding JSON.");
        snprintf(callState->json, MALLOC_BUFFER_SIZE, "%s},\"count\":%d}\n", callState->json, msgCount);
    }
    
    msgCount++;

    __log__("[parse_returnValue] Exit.");
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations" // this is so we can dereference ->isa
static inline BOOL is_object_safe_to_log(id paramVal) {
    __log__("[is_object_safe_to_log] Checking pointers");
    if( !(is_valid_pointer(paramVal)) || !(is_valid_pointer(((struct objc_object *)(paramVal))->isa))) {
        return FALSE;
    }

    __log__("[is_object_safe_to_log] Getting class");
    Class cls = object_getClass(paramVal);
    
    if(!is_valid_pointer(cls) || !(is_valid_pointer(((struct objc_object *)(cls))->isa)) || cls != ((struct objc_object *)(paramVal))->isa) {
        __log__("[is_object_safe_to_log] Shit was false");
        return FALSE;
    }

    __log__("[is_object_safe_to_log] Getting className");
    const char *className = object_getClassName(paramVal);

    __log__("[is_object_safe_to_log] Checking validity of className pointer");
    if( !(is_valid_pointer((void *)className))) {
        return FALSE;
    }
    
    return TRUE;
}

static inline BOOL is_object_on_safe_list(id paramVal) {
    const char *className = object_getClassName(paramVal);
    __log__("[is_object_safe_to_log] Getting NSString version of \"%s\"", className);
    NSString *objectName = orig_objc_msgSend(objc_getClass("NSString"), @selector(stringWithUTF8String:), className);
    if(!(is_valid_pointer(objectName))) {
        //NSLog(@"[is_object_safe_to_log] NSString fail");
        return FALSE;
    }
    
    __log__("[is_object_safe_to_log] Checking to see if it's a loggable type");
    if( !(orig_objc_msgSend(loggableClasses, @selector(containsObject:), objectName))) {
        //NSLog(@"[is_object_safe_to_log] Not on the list");
        return FALSE;
    }
    
    return TRUE;
}
#pragma clang diagnostic pop

/*
    returns something that looks like this:

        "type":"int", "value":"31337"
*/
extern "C" USED inline char *parameter_to_JSON(char *typeCode, void *paramVal) {
    char *json;
    BOOL isPointer = FALSE;

    __log__("[parameter_to_JSON] Entry");    
    if(!typeCode || !is_valid_pointer((void *)typeCode)) {
        __log__("Abandoning parameter_to_JSON");
        return strdup("\"BADPTR\"");
    }

    // lololol
    unsigned long v = (unsigned long)paramVal;
    double d = (double)v;

    // Make a nice juicy buffer to hold the JSON blob
    json = (char *)malloc(MALLOC_BUFFER_SIZE);
    if(!json)
        return strdup("\"MALLOC_FAIL\"");
    *json = 0;

    // Take note of whether or not we're dealing with a pointer
    __log__("[parameter_to_JSON] Typecode: '%s'", typeCode);
    if(typeCode[0] == '^') {
        __log__("[parameter_to_JSON] typeCode is a pointer.");
        isPointer = TRUE;
        typeCode = &typeCode[1];
    }

    switch(*typeCode) {
        case 'c': // char
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"char\",\"value\":\"0x%lx (%d) ('%c')\"", (unsigned long)paramVal, (int)(long)paramVal, ((int)(long)paramVal >= 0x20 && isprint((long)paramVal)) ? (int)((long)paramVal) : 0x20); 
            break;
        case 'i': // int
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"int\",\"value\":\"0x%lx (%ld)\"", (long)paramVal, (long)paramVal); 
            break;
        case 's': // short
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"short\",\"value\":\"0x%lx (%ld)\"", (long)paramVal, (long)paramVal); 
            break;
        case 'l': // long
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"long\",\"value\":\"0x%lx (%ld)\"", (long)paramVal, (long)paramVal); 
            break;
        case 'q': // long long
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"long long\",\"value\":\"%llx (%lld)\"", (long long)paramVal, (long long)paramVal); 
            break;
        case 'C': // unsigned char
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"unsigned char\",\"value\":\"0x%lx (%lu) ('%c')\"", (unsigned long)paramVal, (unsigned long)paramVal, ((int)(long)paramVal >= 0x20 && isprint((long)paramVal)) ? (int)(long)paramVal : 0x20); 
            break;
        case 'I': // unsigned int
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"unsigned int\",\"value\":\"0x%lx (%lu)\"", (unsigned long)paramVal, (unsigned long)paramVal); 
            break;
        case 'S': // unsigned short
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"unsigned short\",\"value\":\"0x%lx (%lu)\"", (unsigned long)paramVal, (unsigned long)paramVal); 
            break;
        case 'L': // unsigned long
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"unsigned long\",\"value\":\"0x%lx (%lu)\"", (unsigned long)paramVal, (unsigned long)paramVal); 
            break;
        case 'Q': // unsigned long long
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"unsigned long long\",\"value\":\"%llx (%llu)\"", (unsigned long long)paramVal, (unsigned long long)paramVal); 
            break;
        case 'f': // float
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"float\",\"value\":\"%f\"", (float)d); 
            break;
        case 'd': // double                      
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"double\",\"value\":\"%f\"", (double)d); 
            break;
        case 'B': // BOOL
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"BOOL\",\"value\":\"%s\"", ((long)paramVal)?"true":"false");
            break;
        case 'v': // void
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"void\",\"ptr\":\"%p\"", paramVal);
            break;
        case '*': // char *
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"char *\",\"value\":\"%s\",\"ptr\":\"%p\" ", (char *)paramVal, paramVal);
            break;
        case '{': // struct
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"struct\",\"ptr\":\"%p\"", paramVal);
            break;
        case ':': // selector
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"SEL\",\"value\":\"@selector(%s)\"", (paramVal)?"Selector FIXME":"nil");
            break;
        case '?': // usually a function pointer or block
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"function pointer\",\"value\":\"%p\"", paramVal);
            break;
        
        case '@': // object
            __log__("[parameter_to_JSON] obj @");
            if(isPointer) {
                snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"id * (void **)\",\"value\":\"%p\"", paramVal);
            } else {
                if(is_object_safe_to_log((id)paramVal)) {
                    __log__("[parameter_to_JSON] Pointer is valid, checking typecode");
                    if(typeCode[1] == '?') {
                        __log__("[parameter_to_JSON] Skipping code block.");
                        snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"%s\",\"value\":\"<^block: %p>\"", object_getClassName(object_getClass((id)paramVal)), paramVal);
                    } else {
                        if(is_object_on_safe_list((id)paramVal)) {
                            __log__("[parameter_to_JSON] Calling @selector(description)");
                            NSString *objDesc = orig_objc_msgSend((id)paramVal, @selector(description));
                            __log__("[parameter_to_JSON] Got the description");
                            NSString *realDesc = orig_objc_msgSend((id)objDesc, @selector(stringByAddingPercentEscapesUsingEncoding:), NSUTF8StringEncoding);
                            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"%s\",\"value\":\"%s\"", object_getClassName(object_getClass((id)paramVal)), (char *)orig_objc_msgSend(realDesc, @selector(UTF8String)));
                        } else {
                            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"%s\",\"value\":\"%p\"", object_getClassName(object_getClass((id)paramVal)), paramVal);
                        }
                    }
                } else {
                    __log__("[parameter_to_JSON] Pointer isn't loggable, skipping.");
                    snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"%s\",\"value\":\"%p\"", "id", paramVal);
                }
            }
            break;
        
        case '#': // class
            __log__("[parameter_to_JSON] class #");

            if(is_valid_pointer(paramVal)) {
                if(class_respondsToSelector((Class)paramVal, @selector(description))) {
                    NSString *desc = orig_objc_msgSend((id)paramVal, @selector(description));
                    NSString *realDesc = orig_objc_msgSend((id)desc, @selector(stringByReplacingOccurrencesOfString:withString:), @"\"", @"\\\"");
                    snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"%s\",\"value\":\"%s\"", class_getName((Class)paramVal), (char *)orig_objc_msgSend(realDesc, @selector(UTF8String)));
                } else {
                    snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"%s\",\"value\":\"%s\"", class_getName((Class)paramVal), "#BARF. No description. This is probably a bug.");
                }
            } else {
                snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"Unmapped memory address\",\"value\":\"%p\"", paramVal);
            }
            break;
        
        default:
            snprintf(json, MALLOC_BUFFER_SIZE, "\"type\":\"UNKNOWN TYPE.\",\"value\":\"Type code: %s @ %p\"", typeCode, paramVal);
            break;     
    }
    
    __log__("[parameter_to_JSON] returning from parameter_to_JSON");
    return json; // caller must free()
}

extern "C" struct objc_callState *parse_args(id self, SEL _cmd, ...) {
    va_list va;
    struct objc_callState *callState;
    char *methodPtr, *argPtr;
    Method method = nil;
    int numArgs, k, realNumArgs;
    BOOL isInstanceMethod = true;
    char argName[MINIBUF_SIZE];
    Class c;

    __log__("[print_args_v] Entry");

    // Gracefully handle and bad pointers passed to objc_msgSend
    if(!self || !_cmd || !msgSpy) {
        __log__("[print_args_v] Abandon ship! NULL pointers passed as objc_msgSend(%p, %p, %p)", self, _cmd, msgSpy);
        return NULL;
    }

    // needed for all the things
    c = object_getClass(self); //->isa; 

    callState = (struct objc_callState *)malloc(sizeof(struct objc_callState *));
    if(!callState) {
        __log__("[print_args_v] callState couldn't be malloc'd. Returning.");
        return NULL;
    }
    
    callState->className = (char *)object_getClassName(self);
    callState->selectorName = (char *)sel_getName(_cmd);

    // We need to determine if "self" is a meta class or an instance of a class.
    // We can't use Apple's class_isMetaClass() here because it seems to randomly crash just
    // a little too often. Always class_isMetaClass() and always in this piece of code. 
    // Maybe it's shit, maybe it's me. Whatever.
    // Instead we fudge the same functionality, which is nice and stable.
    // 1. Get the name of the object being passed as "self"
    // 2. Get the metaclass of "self" based on its name
    // 3. Compare the metaclass of "self" to "self". If they're the same, it's a metaclass.
    //bool meta = (objc_getMetaClass(className) == object_getClass(self));
    //bool meta = (id)c == self;
    bool meta = (objc_getMetaClass(callState->className) == c);
    
    // get the correct method
    if(!meta) {
        __log__("[print_args_v] Dealing with an instance");
        method = class_getInstanceMethod(c, (SEL)_cmd);
    } else {
        __log__("[print_args_v] Dealing with a class");
        method = class_getClassMethod(c, (SEL)_cmd);
        isInstanceMethod = false;
    }
    
    // quick sanity check
    if(!method || !callState->className || !callState->selectorName) {
        return NULL;
    }

    // If logging isn't verbose then just return a stub.
    // Otherwise look up the argument data.
    if(msgSpy->msgSendLoggingEnabled == true) {
        // start the JSON block
        callState->json = (char *)malloc(MALLOC_BUFFER_SIZE);
        if(!callState->json) {
            __log__("[print_args_v] json couldn't be malloc'd. Returning.");
            free(callState);
            return NULL;
        }
        
        // grab the argument count
        numArgs = method_getNumberOfArguments(method);
        realNumArgs = numArgs - 2;

        callState->returnType = method_copyReturnType(method);
        snprintf(callState->json, MALLOC_BUFFER_SIZE, "{\"messageType\":\"objc_msgSend\",\"depth\":%ld,\"thread\":%lu,\"objectAddr\":\"%p\",\"class\":\"%s\",\"method\":\"%s\",\"isInstanceMethod\":%d,\"returnTypeCode\":\"%s\",\"numArgs\":%d,\"args\":{", get_depth(), (unsigned long)pthread_self(), self, callState->className, callState->selectorName, isInstanceMethod, callState->returnType, realNumArgs);

        if(0) { //strcmp(methodName, "description") == 0) {
            __log__("[print_args_v] We're calling 'description'");
        } else {            
            // use this to iterate over argument names
            methodPtr = strdup(callState->selectorName);
            
            __log__("[print_args_v] Dumping args.");
            // cycle through the paramter list for this method.
            // start at k=2 so that we omit Cls and SEL, the first 2 args of every function/method
            va_start(va, _cmd);
            for(k=2; k < numArgs; k++) {
                char argTypeBuffer[MINIBUF_SIZE]; // safe and reasonable limit on var name length
                int argNum = k;
                argNum -= 2;

                // non-destructive strtok() replacement
                __log__("[print_args_v] Starting while loop");
                argPtr = argName;
                while(*methodPtr != ':' && *methodPtr != '\0')
                    *(argPtr++) = *(methodPtr++);
                *argPtr = (char)0;
                ++methodPtr;
                
                // get the type code for the argument
                __log__("[print_args_v] method_getArgumentType");
                method_getArgumentType(method, k, argTypeBuffer, MINIBUF_SIZE);
                if(argTypeBuffer[0] == (char)0) {
                    __log__("[print_args_v] Yikes, method_getArgumentType() failed on arg%d", argNum);
                    continue;
                }
                
                // if it's a pointer then we actually want the next byte.
                //char *typeCode = (argTypeBuffer[0] == '^') ? &argTypeBuffer[1] : argTypeBuffer;
                __log__("[print_args_v] arg%d '%s' has typecode '%s'", argNum, argName, argTypeBuffer);
                
                // start the JSON for this argument
                void *paramVal = va_arg(va, void *);
                char *paramValueJSON = parameter_to_JSON(argTypeBuffer, paramVal);

                if(paramValueJSON) {
                    snprintf(callState->json, MALLOC_BUFFER_SIZE, "%s\"%s\":{%s}%c", callState->json, argName, paramValueJSON, (k==numArgs-1)?'\0':',');
                    free(paramValueJSON);
                }
            }
            free(methodPtr);
        }
        __log__("[print_args_v] Finished [%s %s]. json: %s", callState->className, callState->selectorName, callState->json);
    } else {
        free(callState);
        callState = NULL;
    }
    
    va_end(va);
    // caller must free() callState->json and callState->returnType and callState
    return callState;
}

