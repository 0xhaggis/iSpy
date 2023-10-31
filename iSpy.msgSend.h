#ifndef ___ISPY_MSGSEND_COMMON___
#define ___ISPY_MSGSEND_COMMON___
//#include <tr1/unordered_set>
//#include <tr1/unordered_map>
#include <unordered_map>

// Uncomment the next line to do crazy verbose logging inside objc_msgSend.
// Be aware this will basically grind your app to a halt. 
// It's useful for debugging crashes, but too much overhead otherwise.

//#define DO_SUPER_DEBUG_MODE 1

#ifdef DO_SUPER_DEBUG_MODE
#define __log__(...) ispy_log(__VA_ARGS__)
#else
#define __log__(...) {}
#endif

// Important. Don't futz.
struct objc_callState {
	const char *className;
	const char *selectorName;
	char *json;
	char *returnType;
};

extern "C" USED int is_valid_pointer(void *ptr);
extern "C" USED const char *get_param_value(id x);
extern "C" struct objc_callState *parse_args(id self, SEL _cmd, ...);
extern "C" USED char *parameter_to_JSON(char *typeCode, void *paramVal);
extern "C" unsigned int is_this_method_on_watchlist(id Cls, SEL selector);
extern "C" inline void parse_returnValue(void *returnValue, struct objc_callState *callState);

#endif
