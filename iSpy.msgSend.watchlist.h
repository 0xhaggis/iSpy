#ifndef __ISPY_OBJC_MSGSEND_WATCHLIST__
#define __ISPY_OBJC_MSGSEND_WATCHLIST__
//#include <tr1/unordered_set>
//#include <tr1/unordered_map>
#include <unordered_map>
#define INTERESTING_CALL 1

struct interestingCall {
    const char *classification;
    const char *className;
    const char *methodName;
    const char *description;
    const char *risk;
    int type;
};

typedef std::unordered_map<std::string, unsigned int> MethodMap_t;
typedef std::unordered_map<std::string, MethodMap_t > ClassMap_t;
typedef std::pair<std::string, MethodMap_t> ClassPair_t;

// Helper functions
void watchlist_startup();
NSDictionary *watchlist_copy_watchlist();
void watchlist_add_app_classes();
void watchlist_add_hardcoded_interesting_calls();
void watchlist_add_method_real(std::string *className, std::string *methodName, unsigned int type, BOOL shouldSendUpdate);
void watchlist_add_method(std::string *className, std::string *methodName, unsigned int type);
void watchlist_remove_method_real(std::string *className, std::string *methodName, BOOL shouldRefresh);
void watchlist_remove_method(std::string *className, std::string *methodName);
void watchlist_remove_class(std::string *className);
void watchlist_clear_watchlist();
int watchlist_is_class_on_watchlist(char *classNameStr);
void watchlist_add_audit_data_to_watchlist(NSArray *JSON);
void watchlist_send_websocket_update(const char *messageType, const char *className, const char *methodName);

#define WATCHLIST_AUDIT 2
#define WATCHLIST_PRESENT 1
#define WATCHLIST_NOT_PRESENT 0

#endif // __ISPY_OBJC_MSGSEND_WATCHLIST__
