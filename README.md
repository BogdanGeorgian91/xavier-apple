# Xavier

Your network. Your rules. Xavier puts you in control of every connection your iOS apps make.

- See every network request in real time
- Catch apps phoning home in the background
- Deep-inspect HTTPS traffic with a local proxy
- Block trackers, ads, and unwanted domains
- Rewrite requests and strip scripts from any host
- Built for developers who want to debug live app traffic

## What it does

Most apps quietly connect to servers you'd never approve — trackers, ad networks, mystery domains. Xavier makes all of that visible.

**Real-time connection monitor.** Get notified the moment any app on your device reaches out to a remote server. No guesses, no surprises.

**Background activity exposed.** Apps don't stop talking when you put your phone down. Xavier logs every background request so you can see what's really going on.

**HTTPS deep inspection.** Xavier runs a local TLS proxy that decrypts and inspects HTTPS traffic from mapped apps. Install the self-signed CA certificate, trust it in Settings, and explore every request and response — headers, bodies, status codes — grouped by site and app.

**Custom blocking rules.** Build your own allowlist or blocklist. Block trackers, ad networks, or any domain you don't trust — across all apps at once.

**Request modification and script stripping.** Add custom headers, rewrite URLs, modify request content, or strip `<script>` tags from any host — all from the Inspector controls.

**Developer debugging.** Shipping an app? Monitor its production network behavior live, test how it handles offline scenarios, and trace connection failures.

**Privacy first.** Your traffic data stays on your device. Always. Nothing is collected, transmitted, or sold.

## How it works

Xavier uses two iOS Network Extension types:

- **NEFilterDataProvider** — monitors all outbound network traffic and enforces blocking rules in near real-time. iOS itself evaluates per-flow verdicts, so blocking is instant and lightweight.
- **NEAppProxyProvider** — transparently proxies HTTPS traffic from mapped apps through a local TLS man-in-the-middle, letting you inspect encrypted connections at the request level. Generic mapped apps live in `Xavier/Info.plist` under `NETestAppMapping`. Private mapped apps live in the ignored `Config/NETestAppMapping.local.plist` file and are merged into the built app during development builds.

The proxy generates a root CA on-device. Install and trust the certificate, enable the proxy profile, and Xavier can decrypt traffic from any mapped app for detailed inspection.

## Architecture: current approach vs. VPN-based approach

Xavier currently uses `NEFilterDataProvider` for traffic monitoring and blocking. There is an alternative architecture — used by apps like Surge and Proxyman — that relies on `NETunnelProviderManager` (a local VPN tunnel) instead. Each approach has trade-offs:

### Current approach: NEFilterDataProvider (content filter)

**How it works:** iOS itself intercepts every outbound connection and asks the filter extension for a verdict — allow, drop, or inspect. The filter never touches packets it doesn't need to care about.

**Benefits:**
- **No VPN badge** — no status bar icon, no visual noise. The filter runs silently.
- **Zero overhead for allowed traffic** — iOS handles routing for allowed flows natively. Your extension only wakes up for new connections.
- **Per-flow verdicts** — each connection gets an individual allow/drop decision before it even starts. Blocking is instant.
- **Browser flow peeking** — the `peekInboundBytes` / `peekOutboundBytes` API lets you observe HTTP traffic data in chunks without setting up a full MITM proxy. Lightweight inspection for non-HTTPS flows.
- **Selective interception** — only the flows you care about are processed. Everything else passes through untouched at near-zero cost.
- **Battery-friendly** — the filter extension is dormant most of the time. iOS only wakes it for new flow decisions.

**Limitations:**
- **No consumer App Store path** — Apple does not allow content filter apps on the App Store for general consumers. The `NEFilterDataProvider` API is restricted to supervised devices for distribution outside of development.

### Alternative approach: NETunnelProviderManager (local VPN)

**How it works:** A local VPN tunnel captures all device traffic through a virtual network interface (TUN). Your code processes every packet, decides what to block or allow, and forwards the rest.

**Benefits:**
- **App Store distribution** — this is how Surge, Proxyman, and similar apps reach consumers. Apple permits Personal VPN entitlements for developer tools.
- **Massive potential user base** — opens up the entire iOS user base, not just developers building from source.

**Trade-offs vs. the current approach:**
- **The VPN badge is not the main issue** — Xavier's app proxy may already show a VPN indicator. The stronger trade-offs are app identity, complexity, and traffic volume.
- **Weaker app identity** — `NEFilterDataProvider` gives Xavier `sourceAppIdentifier`, and `NEAppProxyProvider` gives app metadata for proxied flows. A packet tunnel mostly sees raw IP packets, not a reliable "this came from Instagram" identifier. Per-app blocking becomes much harder, and may be impossible without enterprise per-app VPN configuration.
- **No iOS-native allow/drop verdicts** — `NEFilterDataProvider` lets iOS ask, "allow or drop this flow?" In a packet tunnel, your code must process packets and decide what to do with them.
- **Much more networking infrastructure** — DNS handling, TCP/UDP flow reconstruction, connection tracking, routing, packet forwarding, failure behavior, and performance tuning become your responsibility.
- **All traffic routed through the extension** — even traffic you don't care about must pass through your code. Higher CPU, memory, and battery usage compared to a filter that only wakes for flow decisions.
- **No browser flow peeking** — the elegant `peekBytes` API for observing browser data in chunks doesn't exist in the VPN world. You'd need the full MITM proxy just to see HTTP-level details.
- **More complex debugging** — a misbehaving VPN tunnel can break all connectivity. A filter extension failure simply allows the flow through.

### Summary

| | Content filter (current) | Local VPN tunnel |
|---|---|---|
| App Store | No | Yes |
| VPN badge | Possible via proxy | Always visible |
| App identity | Strong app-level metadata | Weak raw-packet metadata |
| Blocking mechanism | iOS-native per-flow verdict | Custom packet processing |
| Battery impact | Minimal | Higher (all traffic routed) |
| Browser data peeking | Built-in | Not available |
| Implementation complexity | Lower | Higher |
| Personal use (Xcode) | Works as-is | Requires rewrite |

Xavier uses the content filter approach because it fits personal tracker blocking and debugging: stronger app attribution, native per-flow blocking, lower overhead, and less networking code. A future App Store version could switch to the VPN approach to reach a broader audience, with the trade-offs described above.

| Goal | Better approach |
|---|---|
| Personal tracker blocking/debugging | Current `NEFilterDataProvider` + `NEAppProxyProvider` |
| Consumer App Store app | `NETunnelProviderManager` |
| Per-app attribution/control | Current approach |
| Maximum distribution | VPN tunnel approach |

## Who this is for

Xavier is built for **technical users with an Apple Developer account**. You need to:

- Build the project from source in Xcode
- Supply your own development team and bundle identifier
- Run it on your device via Xcode (development build)

**You do not need a supervised device for personal use.** Building and running directly from Xcode to your own device works without MDM or configuration profiles. The `NEFilterDataProvider` and `NEAppProxyProvider` entitlements in the project are sufficient for development builds. `Xavier/Info.plist` provides generic `NETestAppMapping` defaults, and `Config/NETestAppMapping.local.plist` lets you add private app bundle IDs without committing them.

A supervised device (or MDM) is only required if you want to distribute the configuration profiles to other people's devices outside of Xcode.

This is not a consumer app you download and tap "enable." It's a developer tool for people who want full visibility into — and control over — their device's network traffic.

## FAQ

### Can I get this on the App Store?
Not in its current form. Apple restricts network content filters for consumer App Store distribution, so the `NEFilterDataProvider`-based architecture can't ship on the App Store. The proxy component (`NEAppProxyProvider`) is more permissive but still requires entitlements Apple scrutinizes heavily. See the architecture section above for the alternative VPN-based approach that could enable App Store distribution.

### How do I build and run it?
1. Open the project in Xcode
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`
3. Set `XAVIER_DEVELOPMENT_TEAM` and `XAVIER_BUNDLE_ID` in `Config/Local.xcconfig`
4. Optional: copy `Config/NETestAppMapping.local.plist.example` to `Config/NETestAppMapping.local.plist` and add private app bundle IDs there
5. Build and run on your device

No supervised device needed for personal development use. The filter and proxy extensions work as-is when sideloaded through Xcode.

**Note:** With a free Apple Developer account, the provisioning profile expires every 7 days and must be rebuilt. A paid Apple Developer account ($99/year) extends this to a full year.
