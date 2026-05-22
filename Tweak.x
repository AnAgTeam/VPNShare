#include <substrate.h>
#include <xpc/xpc.h>
#include <dlfcn.h>
#import <Foundation/Foundation.h>

extern const char *const kPFAction;

enum {
	PF_PASS          = 0,
	PF_DROP          = 1,
	PF_SCRUB         = 2,
	PF_NOSCRUB       = 3,
	PF_NAT           = 4,
	PF_NONAT         = 5,
	PF_BINAT         = 6,
	PF_NOBINAT       = 7,
	PF_RDR           = 8,
	PF_NORDR         = 9,
	PF_SYNPROXY_DROP = 10,
	PF_DEFER         = 11,
	PF_MATCH         = 12,
};

static int64_t (*orig_PFUserBeginRules)(int64_t);
static int64_t (*orig_PFUserCommitRules)(int64_t, int64_t, int64_t, int64_t);
static int64_t (*orig_PFUserAddRule)(int64_t, int64_t, xpc_object_t);

static int64_t hook_PFUserBeginRules(int64_t a1) {
	return 1;
}

static int64_t hook_PFUserCommitRules(int64_t a1, int64_t a2, int64_t a3, int64_t a4) {
	return 1;
	//return orig_PFUserCommitRules(a1, a2, a3, a4);
}

static int64_t hook_PFUserAddRule(int64_t a1, int64_t a2, xpc_object_t rule) {
	if (rule && xpc_get_type(rule) == XPC_TYPE_DICTIONARY) {
		uint64_t pf_action = xpc_dictionary_get_uint64(rule, kPFAction);
		if (pf_action == PF_NAT || pf_action == PF_NONAT || pf_action == PF_RDR ||
			pf_action == PF_PASS || pf_action == PF_DROP || pf_action == PF_SCRUB ||
			pf_action == PF_MATCH) {
			// return success
			return 1;
		}
	}
	return 1;
	//return orig_PFUserAddRule(a1, a2, rule);
}

%ctor {
	void *begin = dlsym(RTLD_DEFAULT, "PFUserBeginRules");
	void *commit = dlsym(RTLD_DEFAULT, "PFUserCommitRules");
	void *add    = dlsym(RTLD_DEFAULT, "PFUserAddRule");
	if (commit) MSHookFunction(begin, (void *)hook_PFUserBeginRules, (void **)&orig_PFUserBeginRules);
	if (commit) MSHookFunction(commit, (void *)hook_PFUserCommitRules, (void **)&orig_PFUserCommitRules);
	if (add)    MSHookFunction(add,    (void *)hook_PFUserAddRule,    (void **)&orig_PFUserAddRule);
}
