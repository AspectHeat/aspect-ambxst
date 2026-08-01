#!/usr/bin/env bash
# Runs the pure NordVPN parsers against every committed fixture.
#
# Why this can exist at all: modules/services/nordvpn-parse.js and nordvpn-iso.js are
# .pragma library files with no QML imports, no Config, and no side effects, so they load
# in plain node. No Quickshell, no compositor, no NordVPN subscription required.
#
# Adding a fixture is adding a test: drop <name>.txt next to a <name>.expected.json.
#
#   ./lab/test-nordvpn-parse.sh          # all fixtures
#   ./lab/test-nordvpn-parse.sh status   # only fixtures matching a substring
#
# Exits non-zero on the first mismatch, so it is usable as a commit gate.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

if ! command -v node >/dev/null 2>&1; then
    echo "test-nordvpn-parse: node is required but not installed" >&2
    exit 127
fi

exec node - "${1:-}" <<'NODE'
const fs = require("fs");
const path = require("path");

const FILTER = process.argv[2] || "";
const FIXTURES = "lab/fixtures/nordvpn";

// .pragma library is not valid JS; strip it and evaluate the rest.
function loadLibrary(file, exported) {
    const src = fs.readFileSync(file, "utf8").replace(/^\s*\.pragma\s+library\s*/, "");
    const tail = exported.map(n => `exports.${n}=typeof ${n}!=="undefined"?${n}:undefined;`).join("");
    const mod = {};
    new Function("exports", src + ";" + tail)(mod);
    return mod;
}

const P = loadLibrary("modules/services/nordvpn-parse.js",
    ["parseStatus", "parseAccount", "parseSettings", "parseGroups", "parseList"]);
const ISO = loadLibrary("modules/services/nordvpn-iso.js",
    ["CODES", "DISPLAY_OVERRIDES", "codeFor", "displayName", "flagFor"]);

let pass = 0, fail = 0;
const problems = [];

function fmt(v) { return JSON.stringify(v); }

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

    let got;
    switch (spec.parser) {
        case "status":   got = P.parseStatus(raw); break;
        case "settings": got = P.parseSettings(raw); break;
        case "groups":   got = P.parseGroups(raw); break;
        case "list":     got = P.parseList(raw); break;
        case "account": {
            const exitFile = txt + ".exit";
            const exitCode = spec.exitCode !== undefined ? spec.exitCode
                : (fs.existsSync(exitFile) ? Number(fs.readFileSync(exitFile, "utf8").trim()) : 0);
            got = P.parseAccount(raw, exitCode);
            break;
        }
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

    // expect: subset assertion. Supports dotted paths ("has.killSwitch") so nested
    // capability flags can be locked in.
    const dig = (obj, path) => path.split(".").reduce((o, k) => (o ?? {})[k], obj);
    for (const [k, v] of Object.entries(spec.expect || {}))
        check(`${base}.${k}`, dig(got, k) === v, `got ${fmt(dig(got, k))} want ${fmt(v)}`);

    // refute: keys that must NOT be present (privacy - assigned IP must never surface).
    for (const k of spec.refute || [])
        check(`${base} refutes ${k}`, got[k] === undefined,
            `leaked ${k}=${fmt(got[k])} - assigned IP must be dropped at the parser boundary`);

    if (spec.count !== undefined) {
        const list = spec.countKey ? got[spec.countKey] : got;
        check(base + " [count]", Array.isArray(list) && list.length === spec.count,
            `got ${Array.isArray(list) ? list.length : fmt(list)} want ${spec.count}`);
    }

    for (const needle of spec.includes || []) {
        const list = spec.countKey ? got[spec.countKey] : got;
        check(`${base} includes ${needle}`, Array.isArray(list) && list.includes(needle),
            `not found in parsed list`);
    }
}

// ------------------------------------------------------------------ ISO map integrity
if (!FILTER || "iso".includes(FILTER)) {
    const countries = P.parseList(fs.readFileSync(path.join(FIXTURES, "countries.txt"), "utf8"));
    const keys = Object.keys(ISO.CODES);
    const missing = countries.filter(c => !ISO.CODES[c]);
    const orphan = keys.filter(k => !countries.includes(k));
    check("iso: every CLI country mapped", missing.length === 0, `unmapped: ${fmt(missing)}`);
    check("iso: no orphaned entries", orphan.length === 0, `orphaned: ${fmt(orphan)}`);
    check("iso: all codes well-formed",
        keys.every(k => /^[A-Z]{2}$/.test(ISO.CODES[k])),
        `malformed: ${fmt(keys.filter(k => !/^[A-Z]{2}$/.test(ISO.CODES[k])))}`);
    const byCode = {};
    keys.forEach(k => { (byCode[ISO.CODES[k]] = byCode[ISO.CODES[k]] || []).push(k); });
    const dupes = Object.entries(byCode).filter(([, v]) => v.length > 1);
    check("iso: no duplicate codes", dupes.length === 0, `duplicates: ${fmt(dupes)}`);
    check("iso: overrides are all real countries",
        Object.keys(ISO.DISPLAY_OVERRIDES).every(k => countries.includes(k)),
        `stale override(s)`);
    check("iso: flagFor rejects junk",
        ISO.flagFor("") === "" && ISO.flagFor("USA") === "" && ISO.flagFor("1!") === "",
        `bad code should yield "" so the UI can fall back to an ISO badge`);
    check("iso: flagFor builds a pair", ISO.flagFor("JP") === "\u{1F1EF}\u{1F1F5}", `got ${fmt(ISO.flagFor("JP"))}`);
    check("iso: displayName expands underscores", ISO.displayName("New_Zealand") === "New Zealand", "");
    check("iso: displayName honors overrides", ISO.displayName("Isle_Of_Man") === "Isle of Man", "");
}

// ------------------------------------------------------------------ adversarial, inline
if (!FILTER || "adversarial".includes(FILTER)) {
    // The v1 bug: an unrecognized status must never be reported as "disconnected".
    for (const junk of ["Status: \n", "\n\n\n", "garbage with no colon", "Status: Reconnecting"])
        check("adversarial: junk status is not disconnected",
            P.parseStatus(junk).state !== "disconnected",
            `${fmt(junk)} yielded "disconnected"`);

    // Truncated mid-line must not throw.
    check("adversarial: truncated status survives",
        (() => { try { return P.parseStatus("Status: Connected\nCoun").state === "connected"; }
                 catch (e) { return false; } })(), "threw or misparsed");

    // A value containing colons must survive (IPv6, transfer strings).
    check("adversarial: colon in value preserved",
        P.parseStatus("Status: Connected\nUptime: 1:02:03").uptime === "1:02:03",
        `got ${fmt(P.parseStatus("Status: Connected\nUptime: 1:02:03").uptime)}`);

    // A banner line must not become a country.
    check("adversarial: list rejects prose",
        !P.parseList("A new version is available!\nJapan\n").includes("A new version is available!"),
        "prose leaked into list");

    // Empty input must be inert, not a crash.
    check("adversarial: empty list", P.parseList("").length === 0, "");
    check("adversarial: empty settings", P.parseSettings("").technology === "", "");
    check("adversarial: empty groups", P.parseGroups("").supportsP2p === false, "");

    // Daemon-down must be distinguishable from logged-out, or the UI sends the user to a
    // login flow that cannot succeed.
    check("adversarial: daemon down != logged out",
        P.parseAccount("Whoops! Cannot reach System Daemon.", 1).daemonReachable === false,
        "daemon error misread as a login problem");
    check("adversarial: logged out is reachable",
        P.parseAccount("You're not logged in.", 1).daemonReachable === true, "");
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
