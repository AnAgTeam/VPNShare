#include <xpc/xpc.h>
#import <Foundation/Foundation.h>

// --- Block all PF (Packet filter) configuration --
// Block configuration that redirects all traffic from
// bridge100 (bridge from Wi-Fi/USB) to pdp_ip0 (carrier)
// This allows hotspot traffic to be passed to VPN tunnel,
// but seems to block non-VPN setup

extern int64_t PFUserBeginRules(int64_t);
extern int64_t PFUserCommitRules(int64_t, int64_t, int64_t, int64_t);
extern int64_t PFUserAddRule(int64_t, int64_t, xpc_object_t);

%hookf(int64_t, PFUserBeginRules, int64_t a1) {
	return 1;
}

%hookf(int64_t, PFUserCommitRules, int64_t a1, int64_t a2, int64_t a3, int64_t a4) {
	return 1;
}

%hookf(int64_t, PFUserAddRule, int64_t a1, int64_t a2, xpc_object_t rule) {
	return 1;
}
