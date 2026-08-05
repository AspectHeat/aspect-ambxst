#!/usr/bin/env bash
# Runs the pure AirVPN parsers against every committed fixture.
#
# Why this can exist at all: modules/services/airvpn-parse.js is a .pragma library file with
# no QML imports, no Config, and no side effects, so it loads in plain node. No Quickshell, no
# compositor, no AirVPN subscription required.
#
# Adding a fixture is adding a test: drop <name>.txt next to a <name>.expected.json.
#
#   ./lab/test-airvpn-parse.sh            # all fixtures + inline checks
#   ./lab/test-airvpn-parse.sh status     # only fixtures matching a substring
#
# Exits non-zero on the first mismatch, so it is usable as a commit gate.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

if ! command -v node >/dev/null 2>&1; then
    echo "test-airvpn-parse: node is required but not installed" >&2
    exit 127
fi

exec node - "${1:-}" <<'NODE'
const fs = require("fs");
const path = require("path");

const FILTER = process.argv[2] || "";
const FIXTURES = "lab/fixtures/airvpn";

// .pragma library is not valid JS; strip it and evaluate the rest.
function loadLibrary(file, exported) {
    const src = fs.readFileSync(file, "utf8").replace(/^\s*\.pragma\s+library\s*/, "");
    const tail = exported.map(n => `exports.${n}=typeof ${n}!=="undefined"?${n}:undefined;`).join("");
    const mod = {};
    new Function("exports", src + ";" + tail)(mod);
    return mod;
}

const P = loadLibrary("modules/services/airvpn-parse.js", [
    "stripTimestamps", "contentLines", "isBoilerplate", "labelMap",
    "detectsCredentialPrompt", "parseRunControl", "parseBluetitStatus",
    "parseConnectionDetail", "normalizeVpnType", "vpnTypeArgument", "columnSpans",
    "parseCountryList", "parseKeyList", "buildConnectArgv", "flagFor"
]);

let pass = 0, fail = 0;
const problems = [];

const fmt = v => JSON.stringify(v);
const dig = (obj, p) => p.split(".").reduce((o, k) => (o ?? {})[k], obj);

function check(name, cond, detail) {
    if (cond) { pass++; return true; }
    fail++;
    problems.push(`${name}: ${detail}`);
    return false;
}

// ------------------------------------------------------------------ fixture-driven
for (const expectFile of fs.readdirSync(FIXTURES).filter(f => f.endsWith(".expected.json")).sort()) {
    const base = expectFile.replace(/\.expected\.json$/, "");
    if (FILTER && !base.includes(FILTER)) continue;

    const spec = JSON.parse(fs.readFileSync(path.join(FIXTURES, expectFile), "utf8"));
    const txt = path.join(FIXTURES, base + ".txt");
    if (!fs.existsSync(txt)) { check(base, false, `missing fixture ${base}.txt`); continue; }
    const raw = fs.readFileSync(txt, "utf8");

    const exitFile = txt + ".exit";
    const exitCode = spec.exitCode !== undefined ? spec.exitCode
        : (fs.existsSync(exitFile) ? Number(fs.readFileSync(exitFile, "utf8").trim()) : 0);

    let got;
    switch (spec.parser) {
        case "status":     got = P.parseBluetitStatus(raw, exitCode); break;
        case "countries":  got = P.parseCountryList(raw); break;
        case "keys":       got = P.parseKeyList(raw); break;
        case "runcontrol": got = P.parseRunControl(raw); break;
        default: check(base, false, `unknown parser ${fmt(spec.parser)}`); continue;
    }

    // expectExact: every key must match AND no unexpected extra keys.
    if (spec.expectExact) {
        const gotKeys = Object.keys(got).sort();
        const wantKeys = Object.keys(spec.expectExact).sort();
        check(base + " [keys]", JSON.stringify(gotKeys) === JSON.stringify(wantKeys),
            `keys differ\n    got  ${fmt(gotKeys)}\n    want ${fmt(wantKeys)}`);
        for (const [k, v] of Object.entries(spec.expectExact))
            check(`${base}.${k}`, got[k] === v, `got ${fmt(got[k])} want ${fmt(v)}`);
    }

    // expect: subset assertion, dotted paths supported ("countries.0.code").
    for (const [k, v] of Object.entries(spec.expect || {}))
        check(`${base}.${k}`, dig(got, k) === v, `got ${fmt(dig(got, k))} want ${fmt(v)}`);

    // refute: keys that must NOT be present. Privacy - the exit IP must never surface.
    for (const k of spec.refute || [])
        check(`${base} refutes ${k}`, dig(got, k) === undefined,
            `leaked ${k}=${fmt(dig(got, k))} - the assigned IP must be dropped at the parser boundary`);

    if (spec.count !== undefined) {
        const list = spec.countKey ? dig(got, spec.countKey) : got;
        check(base + " [count]", Array.isArray(list) && list.length === spec.count,
            `got ${Array.isArray(list) ? list.length : fmt(list)} want ${spec.count}`);
    }

    // The header's own "(N)" must agree with how many rows we actually sliced, or a
    // truncated read would silently yield a short country list.
    if (spec.declaredCountMatchesRows) {
        check(base + " [declared == rows]", got.declaredCount === got.countries.length,
            `header says ${fmt(got.declaredCount)}, sliced ${got.countries.length} rows`);
    }

    for (const code of spec.includesCodes || []) {
        check(`${base} includes ${code}`,
            (got.countries || []).some(c => c.code === code), `not found in parsed list`);
    }

    for (const name of spec.includesNames || []) {
        check(`${base} includes name ${fmt(name)}`,
            (got.countries || []).some(c => c.name === name), `not found in parsed list`);
    }

    for (const key of spec.includesKeys || []) {
        check(`${base} includes key ${key}`,
            (got.keys || []).includes(key), `not found in parsed list`);
    }
}

// ------------------------------------------------------------------ connect argv contract
// Plan §9: --async mandatory, network lock off by default, no credentials on argv. These are
// the two rules that can cost the desktop or the remote session, so they are asserted against
// every option combination rather than trusted to a single happy-path fixture.
if (!FILTER || "connect".includes(FILTER)) {
    const COMBOS = [
        {},
        { country: "CH" },
        { country: "Switzerland", vpnType: "openvpn" },
        { country: "NL", vpnType: "wireguard", key: "Default" },
        { server: "Achernar" },
        { server: "Achernar", country: "CH" },
        { networkLock: true, country: "SE" },
        { vpnType: "openvpn", tlsMode: "crypt", ipv6: false,
            allowPrivateNetwork: false, useAirVpnDns: false },
        { vpnType: "OPENVPN", key: "mykey", country: "JP" },
        { country: "", vpnType: "", key: "", server: "" },
        { country: undefined, vpnType: null }
    ];

    for (const combo of COMBOS) {
        const argv = P.buildConnectArgv(combo);
        const label = `connect ${fmt(combo)}`;

        check(`${label} has --async`, argv.includes("--async"), `argv ${fmt(argv)}`);
        check(`${label} has --network-lock`, argv.includes("--network-lock"), `argv ${fmt(argv)}`);

        const lock = argv[argv.indexOf("--network-lock") + 1];
        const wantLock = combo.networkLock === true
            ? (combo.allowPrivateNetwork === false ? "noprivate" : "on") : "off";
        check(`${label} lock=${wantLock}`, lock === wantLock, `got ${fmt(lock)}`);

        check(`${label} calls goldcrest`, argv[0] === "goldcrest", `got ${fmt(argv[0])}`);
        check(`${label} never hummingbird`,
            !argv.some(a => /hummingbird|eddie/i.test(String(a))), `argv ${fmt(argv)}`);

        // A password on argv would be world-readable in /proc for the life of the process.
        check(`${label} no credentials on argv`,
            !argv.includes("--air-user") && !argv.includes("--air-password")
                && !argv.includes("-U") && !argv.includes("-P"),
            `argv ${fmt(argv)}`);

        check(`${label} no empty argv elements`,
            argv.every(a => typeof a === "string" && a.trim() !== ""), `argv ${fmt(argv)}`);

        check(`${label} has explicit IPv6 preference`, argv.includes("--air-ipv6"),
            `argv ${fmt(argv)}`);
    }

    // Server wins over country, and they never both appear: --air-server pins a host and
    // --air-country would be silently ignored.
    const both = P.buildConnectArgv({ server: "Achernar", country: "CH" });
    check("connect: server excludes country",
        both.includes("--air-server") && !both.includes("--air-country"), `argv ${fmt(both)}`);

    // Anything that is not "openvpn" means WireGuard, so a stale or misspelled config value
    // cannot flip the default away from the Suite's own.
    check("connect: vpnType junk falls back to wireguard",
        P.buildConnectArgv({ vpnType: "wireguad" }).includes("wireguard"), "");
    check("connect: vpnType openvpn honored",
        P.buildConnectArgv({ vpnType: "OpenVPN" }).includes("openvpn"), "");
    check("connect: default has no --air-vpn-type",
        !P.buildConnectArgv({}).includes("--air-vpn-type"),
        "an unset type must let Bluetit choose, not be forced");
    const expanded = P.buildConnectArgv({ vpnType: "openvpn", tlsMode: "crypt", ipv6: false,
        allowPrivateNetwork: false, useAirVpnDns: false });
    check("connect: OpenVPN TLS mode honored",
        expanded.includes("--air-tls-mode") && expanded.includes("crypt"), fmt(expanded));
    check("connect: IPv6 off honored",
        expanded[expanded.indexOf("--air-ipv6") + 1] === "off", fmt(expanded));
    const lockedWithoutLan = P.buildConnectArgv({ networkLock: true,
        allowPrivateNetwork: false });
    check("connect: lock without LAN uses noprivate",
        lockedWithoutLan[lockedWithoutLan.indexOf("--network-lock") + 1] === "noprivate",
        fmt(lockedWithoutLan));
    check("connect: LAN preference does not enable lock",
        P.buildConnectArgv({ networkLock: false, allowPrivateNetwork: false })
            [P.buildConnectArgv({ networkLock: false, allowPrivateNetwork: false })
                .indexOf("--network-lock") + 1] === "off", "LAN preference must be inert without lock");
    check("connect: system DNS honored", expanded.includes("--ignore-dns-push"), fmt(expanded));
    check("connect: WireGuard never receives TLS mode",
        !P.buildConnectArgv({ vpnType: "wireguard", tlsMode: "crypt" })
            .includes("--air-tls-mode"), "TLS mode is OpenVPN-only");
}

// ------------------------------------------------------------------ credential prompt guard
// findings.md §1: this is the check that stands between a logged-out machine and a 4 GB/12 s
// stdout flood that OOM-kills the shell.
if (!FILTER || "prompt".includes(FILTER)) {
    check("prompt: detected", P.detectsCredentialPrompt("AirVPN Username: "), "");
    check("prompt: detected with timestamps",
        P.detectsCredentialPrompt("2026-08-04 20:18:56 foo\nAirVPN Username: "), "");
    check("prompt: password form", P.detectsCredentialPrompt("AirVPN Password:"), "");
    check("prompt: repeated loop form",
        P.detectsCredentialPrompt("AirVPN Username: ".repeat(500)), "");
    check("prompt: not in ordinary status",
        !P.detectsCredentialPrompt("Bluetit is not connected"), "false positive");
    check("prompt: not in country list",
        !P.detectsCredentialPrompt(fs.readFileSync(path.join(FIXTURES, "air-list-countries.txt"), "utf8")),
        "false positive would hide the whole country list behind a login card");

    // A prompting status read must NOT be reported as a tunnel state.
    const prompted = P.parseBluetitStatus("AirVPN Username: AirVPN Username: ", 124);
    check("prompt: status -> needsCredentials", prompted.state === "needsCredentials",
        `got ${fmt(prompted.state)}`);
    check("prompt: status not disconnected", prompted.state !== "disconnected", "");
}

// ------------------------------------------------------------------ run control file
if (!FILTER || "runcontrol".includes(FILTER)) {
    const commented = [
        "#", "# goldcrest runcontrol file", "#", "",
        "# air-user            <username>",
        "# air-password        <password>"
    ].join("\n");
    const rc = P.parseRunControl(commented);
    check("rc: all-commented is not configured", rc.credentialsConfigured === false,
        "a commented template must never read as logged in");
    check("rc: all-commented has no user", rc.hasUser === false, "");

    const live = P.parseRunControl("air-user   someone\nair-password   secret\n");
    check("rc: user+password is configured", live.credentialsConfigured === true, "");
    check("rc: user surfaced", live.user === "someone", `got ${fmt(live.user)}`);
    check("rc: password never returned", live.password === undefined,
        "the password must not leave the parser");

    check("rc: user alone is not enough",
        P.parseRunControl("air-user someone\n").credentialsConfigured === false,
        "goldcrest still prompts without a password, which is the prompt-loop hazard");
    check("rc: key alone is not a login",
        P.parseRunControl("air-key Default\n").credentialsConfigured === false,
        "--air-key selects a device key on an already authenticated account");
    check("rc: key detected",
        P.parseRunControl("air-key Default\n").hasKey === true, "");
    check("rc: inline comment not a directive",
        P.parseRunControl("   # air-user someone\n").hasUser === false, "");
    check("rc: empty is inert", P.parseRunControl("").credentialsConfigured === false, "");
    check("rc: null is inert", P.parseRunControl(null).credentialsConfigured === false, "");
}

// ------------------------------------------------------------------ adversarial, inline
if (!FILTER || "adversarial".includes(FILTER)) {
    // The v1 NordVPN bug, ported: an unrecognized status must never be "disconnected".
    for (const junk of ["", "\n\n\n", "garbage with no verbs", "Bluetit is confused",
                        "Network filter and lock is disabled"]) {
        check("adversarial: junk status is not disconnected",
            P.parseBluetitStatus(junk, 0).state !== "disconnected",
            `${fmt(junk)} yielded "disconnected"`);
    }

    // Boilerplate alone must not be read as a state - it is what EVERY invocation prints.
    const bannerOnly = fs.readFileSync(path.join(FIXTURES, "bluetit-status-disconnected.txt"), "utf8")
        .split("\n").filter(l => !/not connected/.test(l)).join("\n");
    check("adversarial: banner-only is not disconnected",
        P.parseBluetitStatus(bannerOnly, 0).state !== "disconnected", "boilerplate read as state");
    check("adversarial: banner-only reports error",
        P.parseBluetitStatus(bannerOnly, 0).state === "error", "");
    check("adversarial: unknownStatus is not a file path",
        !/\/home\/|\.config/.test(P.parseBluetitStatus(bannerOnly, 0).unknownStatus || ""),
        "the run-control path must not be surfaced as a status message");

    // Truncated mid-table must not throw, and must not invent a country.
    const countriesRaw = fs.readFileSync(path.join(FIXTURES, "air-list-countries.txt"), "utf8");
    for (const cut of [40, 200, 420, 700]) {
        const partial = countriesRaw.slice(0, cut);
        check(`adversarial: truncated countries survives @${cut}`,
            (() => { try { return Array.isArray(P.parseCountryList(partial).countries); }
                     catch (e) { return false; } })(), "threw");
    }

    // Timestamp stripping is load-bearing: without it no row or label matches.
    check("adversarial: timestamps stripped",
        P.stripTimestamps("2026-08-04 20:17:25 Bluetit is not connected") === "Bluetit is not connected",
        `got ${fmt(P.stripTimestamps("2026-08-04 20:17:25 Bluetit is not connected"))}`);
    check("adversarial: timestamp inside a message is left alone",
        P.stripTimestamps("Expires 2026-08-04 20:17:25 ok") === "Expires 2026-08-04 20:17:25 ok", "");
    check("adversarial: status parses WITHOUT stripping being skipped",
        P.parseBluetitStatus("2026-08-04 20:17:25 Bluetit is not connected", 0).state === "disconnected",
        "a timestamped line must still classify");

    // Country names with spaces and parentheses are the reason for column slicing.
    const countries = P.parseCountryList(countriesRaw);
    check("adversarial: parenthesised name survives",
        countries.countries.some(c => c.name === "Republic of China (Taiwan)"),
        "whitespace splitting would have truncated this");
    check("adversarial: multiword name survives",
        countries.countries.some(c => c.name === "United States of America"), "");
    check("adversarial: no country name is a bare ISO code",
        countries.countries.every(c => c.name.length > 2), "a column offset is off by one");
    check("adversarial: every code is ISO alpha-2",
        countries.countries.every(c => /^[A-Z]{2}$/.test(c.code)), "");
    check("adversarial: no boilerplate leaked as a country",
        !countries.countries.some(c => /goldcrest|bluetit|openvpn|openssl|copyright/i.test(c.name)), "");
    check("adversarial: load is a percentage or -1",
        countries.countries.every(c => c.load === -1 || (c.load >= 0 && c.load <= 100)), "");
    check("adversarial: servers counted", countries.countries.every(c => c.servers >= 0), "");

    check("adversarial: empty country list is inert",
        P.parseCountryList("").countries.length === 0, "");
    check("adversarial: rule line without rows yields nothing",
        P.parseCountryList("-------- ------------------------------\n").countries.length === 0, "");

    // A list error must be reported, not silently returned as "no countries".
    const notFound = P.parseCountryList(
        fs.readFileSync(path.join(FIXTURES, "air-list-country-notfound.txt"), "utf8"));
    check("adversarial: list error surfaced", notFound.error !== "", "");
    check("adversarial: list error yields no countries", notFound.countries.length === 0, "");

    check("adversarial: empty key list is inert", P.parseKeyList("").keys.length === 0, "");
    check("adversarial: key list rejects boilerplate",
        P.parseKeyList("Goldcrest - AirVPN Bluetit Client 2.1.0 - 15 June 2026\nDefault\n")
            .keys.join(",") === "Default",
        `got ${fmt(P.parseKeyList("Goldcrest - AirVPN Bluetit Client 2.1.0 - 15 June 2026\nDefault\n").keys)}`);

    // Daemon-down must be distinguishable from needing credentials, or the panel offers a
    // login flow that cannot possibly succeed.
    const daemonDown = P.parseBluetitStatus("Cannot connect to Bluetit", 1);
    check("adversarial: daemon down != needs credentials",
        daemonDown.daemonReachable === false && daemonDown.needsCredentials === false, "");
    check("adversarial: permission denied is not reachable",
        P.parseBluetitStatus("Permission denied", 1).daemonReachable === false, "");
    check("adversarial: disconnected IS reachable",
        P.parseBluetitStatus(
            fs.readFileSync(path.join(FIXTURES, "bluetit-status-disconnected.txt"), "utf8"), 0
        ).daemonReachable === true, "");

    // Network lock must be tri-state: on, off, or never reported.
    check("adversarial: lock unknown when unsaid",
        P.parseBluetitStatus("Bluetit is not connected", 0).networkLockKnown === false, "");
    check("adversarial: lock enabled parsed",
        P.parseBluetitStatus("Network filter and lock is enabled\nBluetit is not connected", 0)
            .networkLock === true, "");

    check("adversarial: vpn type normalization",
        P.normalizeVpnType("wireguard") === "WireGuard"
            && P.normalizeVpnType("OPENVPN") === "OpenVPN"
            && P.normalizeVpnType("") === "", "");
    check("adversarial: vpnTypeArgument only ever emits two values",
        ["wireguard", "openvpn"].includes(P.vpnTypeArgument("nonsense"))
            && P.vpnTypeArgument("openvpn") === "openvpn"
            && P.vpnTypeArgument(null) === "wireguard", "");

    check("adversarial: flagFor rejects junk",
        P.flagFor("") === "" && P.flagFor("USA") === "" && P.flagFor("1!") === "" && P.flagFor(null) === "",
        `bad code should yield "" so the UI can fall back to an ISO badge`);
    check("adversarial: flagFor builds a pair",
        P.flagFor("JP") === "\u{1F1EF}\u{1F1F5}", `got ${fmt(P.flagFor("JP"))}`);
    check("adversarial: flagFor is case-insensitive", P.flagFor("ch") === P.flagFor("CH"), "");

    // Privacy: no parser output may carry an IP address.
    const allText = [countriesRaw,
        fs.readFileSync(path.join(FIXTURES, "bluetit-status-disconnected.txt"), "utf8")].join("\n");
    const serialized = JSON.stringify([P.parseCountryList(allText), P.parseBluetitStatus(allText, 0)]);
    check("privacy: no IPv4 in parser output",
        !/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/.test(serialized),
        "an address reached a parsed value");
    check("privacy: no home path in parser output",
        !/\/home\/[a-z]/i.test(serialized), "a filesystem path reached a parsed value");
}

// ------------------------------------------------------------------ committed fixture hygiene
// The repo is public. A fixture is raw CLI output, which is exactly where a captured address
// or home path hides.
if (!FILTER || "hygiene".includes(FILTER)) {
    for (const file of fs.readdirSync(FIXTURES).filter(f => f.endsWith(".txt"))) {
        const raw = fs.readFileSync(path.join(FIXTURES, file), "utf8");
        check(`hygiene: ${file} has no home path`, !/\/home\/[a-z]/i.test(raw),
            "redact to $HOME before committing");
        // Bandwidth figures are dotted decimals, so match only 4-octet dotted quads.
        const ips = raw.match(/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g) || [];
        check(`hygiene: ${file} has no IPv4`, ips.length === 0, `found ${fmt(ips.slice(0, 3))}`);
        check(`hygiene: ${file} carries no credential`,
            !/air-password\s+\S/i.test(raw), "a password reached a committed fixture");
    }
}

// ------------------------------------------------------------------ report
console.log(`\n  ${pass} passed, ${fail} failed\n`);
if (fail) {
    console.log("  failures:");
    problems.forEach(p => console.log("    - " + p));
    console.log("");
    process.exit(1);
}
NODE
