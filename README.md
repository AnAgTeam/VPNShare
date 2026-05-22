# VPNShare

**English** · [Русский](README.ru.md)

A rootless tweak for iOS that suppresses Apple's auto-installed Packet Filter (`pf`)
rules for Personal Hotspot / Internet Sharing. This lets you replace iOS's default
NAT through cellular (`pdp_ip0`) with a custom NAT through any interface — most
notably a VPN tunnel (`utun3`) — and keep that setup stable
across hotspot toggles.

Tested on RootHide. Should also work on Dopamine / palera1n rootless.

A side-effect use case: this can serve as a partial alternative to
[TetherMe](http://www.cobaltapps.com/wp/tetherme-ios-13-update/) on rootless /
RootHide jailbreaks, where TetherMe is unavailable. Since hotspot egress goes
through a VPN tunnel instead of cellular directly, carrier-side tethering
detection (TTL/DPI) becomes much harder. Note: requires a VPN to be running
(see [TODO](#todo)).

## Why

The goal was to share a VPN-tunneled connection from the phone via hotspot —
without running a SOCKS proxy on the device or routing clients through tedious
per-app configurations. Just turn on VPN, enable hotspot, get VPN-routed traffic
on every connected device.

The blocker: iOS's `misd` daemon (`/usr/libexec/misd`) installs its own `pf` rules
every time hotspot toggles, NAT'ing client traffic out through the cellular
interface `pdp_ip0`. A manually-installed `pf` rule routing through `utun3`
gets clobbered by misd's rules on every toggle.

Example of a working manual rule:
```
echo "nat on utun3 from bridge100:network to any -> (utun3)" | sudo pfctl -f -
```
This makes hotspot clients exit via the VPN tunnel — but as soon as misd's
rules come in, the cellular-NAT takes priority and the VPN route stops being
honored.

The cleanest fix turned out to be preventing misd from installing those rules
in the first place. That's what this tweak does.

## What misd installs (and what we strip out)

When hotspot starts, misd populates the `com.apple.internet-sharing/base_v4`
PF anchor with rules like:

```
TRANSLATION RULES:
  nat  on pdp_ip0  inet from 172.20.10.0/28 to any -> (pdp_ip0:0) extfilter ei
  no nat on bridge100 inet from 172.20.10.1 to 172.20.10.0/28
  rdr on bridge100  inet proto tcp from 172.20.10.0/28 to any port = 21 -> 127.0.0.1 port 8021

FILTER RULES:
  scrub on pdp_ip0 all no-df fragment reassemble
  scrub on bridge100 all no-df max-mss 1410 fragment reassemble
  scrub on bridge100 proto esp all no-df fragment reassemble
  pass  on pdp_ip0 all flags any keep state
  pass  on pdp_ip0 proto esp all no state
  pass  on bridge100 all flags any keep state rtable 2
```

The two that matter for our case:
- `nat on pdp_ip0 ...` — forces hotspot client traffic out through cellular
- `pass on bridge100 ... rtable 2` — pins client traffic to a specific routing
  table that doesn't have a VPN default route

By blocking the whole transaction, the anchor stays empty, client traffic falls
through to the system's main routing table, and any custom `pf` rule (e.g., NAT
to `utun3`) takes effect.

## How it works

The PacketFilter framework exports a small user-space API that misd uses to
configure rules transactionally:

- `PFUserBeginRules` — open a transaction (`DIOCXBEGIN` ioctl)
- `PFUserAddRule` — stage one rule (`DIOCADDRULE`)
- `PFUserCommitRules` — finalize (`DIOCXCOMMIT`)

The tweak hooks all three with logos `%hookf` (which under the hood uses
`MSHookFunction` from ElleKit / Substrate-compat) and returns "success"
without forwarding to the originals. Net result: misd thinks it configured
the anchor; the kernel never sees any of it.

```c
%hookf(int64_t, PFUserBeginRules, int64_t a1)                                  { return 1; }
%hookf(int64_t, PFUserCommitRules, int64_t a1, int64_t a2, int64_t a3, int64_t a4) { return 1; }
%hookf(int64_t, PFUserAddRule, int64_t a1, int64_t a2, xpc_object_t rule)      { return 1; }
```

Why hook user-space wrappers and not the ioctl directly — they're simpler to
target, signed for arm64e PAC by `dlsym`, and a single chokepoint for the
anchor we care about.

## Manual approach (without this tweak)

The same effect can be achieved at runtime with `pfctl` alone — useful for
testing, or if you don't want to install anything:

```
sudo pfctl -F all -a com.apple.internet-sharing
```

This clears misd's nested anchors. The catch: misd **overwrites** its own
anchor on every hotspot toggle (off → on rewrites the contents). It does
**not** touch the root ruleset — so your manually-loaded NAT rule for `utun3`
survives a toggle — but the anchor's rules will be back, so you have to
re-run the flush every time you re-enable hotspot. Fiddly enough that
automating it via this tweak is cleaner.

## Usage

1. Install the `.deb` via your package manager (Sileo / Zebra).
2. Set up a VPN. Tested with [ShadowRocket](https://apps.apple.com/app/shadowrocket/id932747118).
   Any VPN client that brings up a `utunN` interface should work in principle,
   but only ShadowRocket has been verified. Find the tunnel interface name
   with `ifconfig`.
3. Once the VPN is up, install a one-time NAT rule routing hotspot traffic
   through it:
   ```
   echo "nat on utun3 from bridge100:network to any -> (utun3)" | sudo pfctl -f -
   ```
4. Enable Personal Hotspot. Connected clients now egress via the VPN.

Without a VPN configured, hotspot will have **no** internet — by design,
since we've removed iOS's default cellular NAT.

## Building

Requirements:
- [theos](https://github.com/theos/theos)
- iOS 16.5 SDK in `$THEOS/sdks/` (or any SDK that still ships
  `PrivateFrameworks/PacketFilter.framework/PacketFilter.tbd` — Xcode 17+ SDKs
  have it removed)
- ElleKit installed on the target device

The repo bundles a minimal set of `xpc/*` headers under `headers/` because
theos's iOS 16.5 SDK ships incomplete (no `xpc/`), and headers copied from
Xcode 26's SDK reference iOS 17+ types that don't exist in older deployment
targets. The bundled headers are stripped down to what's actually needed.

To build and install:
```
make package install THEOS_DEVICE_IP=<phone-ip>
```

The output `.deb` ends up in `packages/`.

## TODO

- **No internet on hotspot without an active VPN.** Since we strip iOS's
  cellular NAT entirely, clients have no egress unless a `utun*` NAT rule is
  active. Should fall back gracefully to cellular when no VPN is running.
- **DNS leaks on connected devices.** The phone itself routes DNS through the
  VPN correctly, but clients on the hotspot don't — their DNS queries appear
  to leak out the cellular path. Probably needs a `pf` redirect for UDP/53
  on `bridge100` to a controlled resolver, or to enforce client DNS via DHCP.
- **Make hooks opt-in via Preferences.** Add a PreferenceLoader / Cephei
  toggle so the tweak can be disabled at runtime without uninstalling.

## File layout

```
.
├── Tweak.x          — logos hooks
├── Makefile         — TARGET, deps, framework links
├── VPNShare.plist   — Filter = Executables = ("misd")  (injects only into misd)
├── control          — Debian package metadata
└── headers/xpc/     — bundled XPC headers (see "Building")
```

## License

No license attached — use at your own risk. Anchored to a single private
daemon's behavior; Apple can break this any update.
