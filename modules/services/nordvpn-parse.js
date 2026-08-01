.pragma library

// Pure parsers for NordVPN CLI output. THE ONLY RECON-GATED FILE in this feature.
//
// Rules (see docs/nordvpn-provider-widget-plan.html §10.0):
//   - No QML imports, no Config, no side effects, no I/O. Plain functions: string in,
//     plain object out. This is what lets lab/test-nordvpn-parse.sh run it under node.
//   - Raw CLI text must never reach a UI component. Everything is normalized here.
//   - Label matching is case-insensitive and order-independent, so a CLI update that
//     reorders or adds lines degrades gracefully instead of breaking.
//
// Verified against NordVPN 5.2.0 on Bostrom; fixtures in lab/fixtures/nordvpn/.
// Anything marked UNVERIFIED could not be captured because the account is logged out,
// and a logged-out CLI never prints the connected form. Treat those as assumptions.

// ---------------------------------------------------------------------------- helpers

// "Key: Value" lines -> { "key": "Value" }, keys lowercased and trimmed.
// Splits on the FIRST colon only, so values containing colons survive (e.g. an IPv6
// address, or "Transfer: 1.2 MiB received").
function labelMap(output) {
    var values = {};
    String(output ?? "").split("\n").forEach(function (line) {
        var separator = line.indexOf(":");
        if (separator < 0)
            return;
        var key = line.slice(0, separator).trim().toLowerCase();
        if (key === "")
            return;
        values[key] = line.slice(separator + 1).trim();
    });
    return values;
}

// `nordvpn countries`, `cities`, and `groups` all emit one bare token per line.
// Verified: fixtures are pure ASCII, no blank lines, no leading/trailing whitespace.
// Filtering and trimming anyway, because that is cheap and a CLI banner would otherwise
// become a fake country.
function parseList(output) {
    return String(output ?? "")
        .split("\n")
        .map(function (line) { return line.trim(); })
        .filter(function (line) { return line !== "" && /^[A-Za-z0-9_\-]+$/.test(line); });
}

function boolFromEnabled(value) {
    return String(value ?? "").trim().toLowerCase() === "enabled";
}

// ---------------------------------------------------------------------------- status

// Only "Disconnected" is verified. The other three are the documented 5.x vocabulary but
// were not observed, hence UNVERIFIED. Anything outside this set becomes "error" rather
// than silently defaulting to "disconnected" — that default is what let v1 clobber the
// logged-out state and report a live tunnel as merely off.
var KNOWN_STATES = {
    "disconnected": "disconnected",  // verified: lab/fixtures/nordvpn/status-disconnected.txt
    "connected": "connected",        // UNVERIFIED
    "connecting": "connecting",      // UNVERIFIED
    "disconnecting": "disconnecting" // UNVERIFIED
};

// Call only when `nordvpn status` exited 0. Non-zero exit is the caller's concern, since
// distinguishing "daemon down" from "logged out" needs the exit code and stderr.
function parseStatus(output) {
    var values = labelMap(output);
    var raw = String(values.status ?? "").trim().toLowerCase();

    var result = {
        state: KNOWN_STATES[raw] ?? "error",
        // UNVERIFIED below this line: the connected form of `nordvpn status` was never
        // captured. Label names are the documented 5.x set. All are empty-safe, and §3 of
        // the plan defines a degradation rule for each, so a wrong guess hides a row
        // rather than breaking the panel.
        country: values.country ?? "",
        city: values.city ?? "",
        server: values.hostname ?? "",
        technology: normalizeTechnology(values["current technology"] ?? values.technology ?? ""),
        protocol: values["current protocol"] ?? values.protocol ?? "",
        transfer: values.transfer ?? "",
        uptime: values.uptime ?? ""
    };

    // Deliberately NOT surfaced: "server ip" / "your new ip". The assigned address is
    // provider-owned runtime state and this is a public repo — plan §5 forbids persisting,
    // logging, or committing it, so it is dropped at the parser boundary where that is
    // easiest to audit.
    if (result.state === "error" && raw !== "")
        result.unknownStatus = raw;

    return result;
}

// ---------------------------------------------------------------------------- account

// Verified: logged out -> exit 1, stdout "You're not logged in."
// A logged-in account prints subscription details, which we neither need nor want, so
// only the boolean is derived. Never parse or retain the email address.
// Phrases are anchored rather than matched as bare substrings. The old pattern also accepted
// "log in" and "login" anywhere in the output, which is a false positive waiting to happen:
// this text is whatever `nordvpn account` prints for a LOGGED-IN account, and one promotional
// line or renewal URL containing "login" would report the user as logged out and pin the setup
// card open right after a successful login. Neither loose alternative was doing any work - the
// observed logged-out output is "You're not logged in.", which contains neither of them.
function parseAccount(output, exitCode) {
    var text = String(output ?? "");
    if (/not logged in|please log in|log in to nordvpn/i.test(text))
        return { loggedIn: false, daemonReachable: true };

    // Distinguish "daemon unreachable" from "logged out": the former is not a login
    // problem and must not send the user to a login flow that cannot succeed.
    if (/daemon|socket|connection refused|permission denied/i.test(text))
        return { loggedIn: false, daemonReachable: false };

    return { loggedIn: Number(exitCode) === 0, daemonReachable: true };
}

// ---------------------------------------------------------------------------- settings

// Verified against lab/fixtures/nordvpn/settings.txt (NordVPN 5.2.0), which prints
// "Technology: NORDLYNX" in caps and every other flag as enabled/disabled.
function normalizeTechnology(value) {
    var normalized = String(value ?? "").trim().toUpperCase();
    if (normalized === "NORDLYNX")
        return "NordLynx";
    if (normalized === "OPENVPN")
        return "OpenVPN";
    return String(value ?? "").trim();
}

function parseSettings(output) {
    var values = labelMap(output);

    // `present` records which labels this CLI build actually emitted, so the panel can
    // hide a control instead of rendering a switch that silently does nothing — the §3
    // degradation contract.
    var present = {};
    Object.keys(values).forEach(function (key) { present[key] = true; });

    return {
        technology: normalizeTechnology(values.technology ?? ""),
        killSwitch: boolFromEnabled(values["kill switch"]),
        autoConnect: boolFromEnabled(values["auto-connect"]),
        lanDiscovery: boolFromEnabled(values["lan discovery"]),
        threatProtection: boolFromEnabled(values["threat protection lite"]),
        firewall: boolFromEnabled(values.firewall),
        routing: boolFromEnabled(values.routing),
        dns: boolFromEnabled(values.dns),
        meshnet: boolFromEnabled(values.meshnet),
        virtualLocation: boolFromEnabled(values["virtual location"]),
        postQuantum: boolFromEnabled(values["post-quantum vpn"]),
        has: {
            technology: present["technology"] === true,
            killSwitch: present["kill switch"] === true,
            autoConnect: present["auto-connect"] === true,
            lanDiscovery: present["lan discovery"] === true,
            threatProtection: present["threat protection lite"] === true,
            virtualLocation: present["virtual location"] === true,
            postQuantum: present["post-quantum vpn"] === true,
            meshnet: present["meshnet"] === true
        }
    };
}

// ---------------------------------------------------------------------------- groups

// Verified: `nordvpn groups` emits Dedicated_IP, Double_VPN, Onion_Over_VPN, P2P,
// Standard_VPN_Servers, Dedicated_Server. The P2P token is exactly "P2P"; matching
// case-insensitively so a rename to "p2p" does not silently hide the mode selector.
function parseGroups(output) {
    var groups = parseList(output);
    var p2p = groups.find(function (group) { return group.toLowerCase() === "p2p"; }) ?? "";
    return { groups: groups, p2pToken: p2p, supportsP2p: p2p !== "" };
}
