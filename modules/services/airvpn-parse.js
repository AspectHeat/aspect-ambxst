.pragma library

// Pure parsers for AirVPN Suite (Goldcrest/Bluetit) CLI output. THE ONLY RECON-GATED FILE
// in this feature, mirroring nordvpn-parse.js.
//
// Rules (see docs/airvpn-provider-widget-plan.html §2, §5):
//   - No QML imports, no Config, no side effects, no I/O. Plain functions: string in,
//     plain object out. That is what lets lab/test-airvpn-parse.sh run it under node.
//   - Raw CLI text must never reach a UI component. Everything is normalized here.
//   - Matching is case-insensitive and order-independent, so a Suite update that reorders
//     or adds lines degrades gracefully instead of breaking.
//
// Verified against AirVPN Suite 2.1.0 on Bostrom; fixtures in lab/fixtures/airvpn/.
// Anything marked UNVERIFIED could not be captured because the account is not logged in on
// Bostrom, and an unauthenticated Goldcrest never prints the connected form. Treat those as
// assumptions, and see docs/airvpn-recon-findings.md.

// ---------------------------------------------------------------------------- helpers

// Every Goldcrest line except the first banner is prefixed "YYYY-MM-DD HH:MM:SS ".
// Stripping is the first thing any parser does; skip it and no label or table row matches.
// Anchored, so a timestamp appearing inside a message body is left alone.
function stripTimestamps(output) {
    return String(output ?? "")
        .split("\n")
        .map(function (line) {
            return line.replace(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} /, "");
        })
        .join("\n");
}

// Timestamp-stripped, right-trimmed, non-empty lines. Left whitespace is PRESERVED because
// the country table is fixed-width and column offsets are meaningful.
function contentLines(output) {
    return stripTimestamps(output)
        .split("\n")
        .map(function (line) { return line.replace(/\s+$/, ""); })
        .filter(function (line) { return line !== ""; });
}

// Goldcrest banner and boilerplate. These are not state and must never be mistaken for it -
// "Reading run control directives from file ..." in particular carries a filesystem path.
function isBoilerplate(line) {
    return /^Goldcrest - |^Bluetit - |^OpenVPN core |^Copyright \(C\)|^OpenSSL |^AirVPN WireGuard Client |^Reading run control directives|^Bluetit options successfully reset/i
        .test(String(line ?? "").trim());
}

// "Key: Value" -> { "key": "Value" }, keys lowercased. Splits on the FIRST colon only so
// values containing colons survive. Used for the UNVERIFIED connected form.
function labelMap(output) {
    var values = {};
    contentLines(output).forEach(function (line) {
        if (isBoilerplate(line))
            return;
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

// ------------------------------------------------------------------- credential prompting

// THE most important function in this file. See findings.md §1.
//
// An unauthenticated `goldcrest --air-user-info` / `--air-key-list` does not fail. It prompts
// on stdin with "AirVPN Username: " and blocks. Quickshell's Process hands its child EOF on
// stdin, and on EOF Goldcrest re-prompts in a tight loop: measured at 3.97 GB of stdout in
// 12 seconds, which would OOM the shell and take the desktop down with it.
//
// The service's first line of defence is never calling those subcommands unless the rc file
// already has credentials. This is the second: any read whose output looks like the prompt is
// classified as "needs credentials" rather than parsed, and the caller kills the process.
function detectsCredentialPrompt(output) {
    return /AirVPN (Username|Password|Key)\s*:/i.test(String(output ?? ""));
}

// ---------------------------------------------------------------------- run control file

// ~/.config/goldcrest.rc is "directive<whitespace>value", # for comments. This - NOT a CLI
// probe - is the authoritative credentials signal, because reading a file cannot hang or
// flood. Values are inspected only for emptiness; the password is never returned.
function parseRunControl(text) {
    var directives = {};
    String(text ?? "").split("\n").forEach(function (line) {
        var trimmed = line.trim();
        if (trimmed === "" || trimmed.charAt(0) === "#")
            return;
        var match = trimmed.match(/^([A-Za-z0-9_-]+)\s+(.*)$/);
        if (!match)
            return;
        directives[match[1].toLowerCase()] = match[2].trim();
    });

    var user = directives["air-user"] ?? "";
    var password = directives["air-password"] ?? "";
    var key = directives["air-key"] ?? "";

    return {
        hasUser: user !== "",
        hasPassword: password !== "",
        hasKey: key !== "",
        // A key alone is not a login: --air-key selects WHICH device key of an already
        // authenticated account to use. Goldcrest still prompts for the username without
        // air-user, so requiring both is what actually prevents the prompt loop.
        credentialsConfigured: user !== "" && password !== "",
        // Never the password itself. Returned so the setup card can say "signed in as X"
        // without the service having to re-read the file.
        user: user
    };
}

// ---------------------------------------------------------------------------- status

// Verified disconnected form (lab/fixtures/airvpn/bluetit-status-disconnected.txt):
//     Network filter and lock is disabled
//     Bluetit is not connected
//
// Connected and disconnected forms are verified against Goldcrest 2.1 fixtures. Per the
// NordVPN lesson, an unrecognized status becomes "error", never "disconnected": that default
// is what let v1 of the NordVPN widget report a live tunnel as merely off.
function parseBluetitStatus(output, exitCode) {
    var text = stripTimestamps(output);
    var lines = contentLines(output).filter(function (line) { return !isBoilerplate(line); });

    var result = {
        state: "error",
        daemonReachable: true,
        needsCredentials: false,
        networkLock: false,
        // Distinguishes "lock is off" from "this build never said", so the panel can hide the
        // row instead of rendering a switch that does nothing.
        networkLockKnown: false,
        country: "",
        server: "",
        technology: ""
    };

    // Ordered most-specific first. A prompt means the read was unauthenticated, which is not
    // a tunnel state at all.
    if (detectsCredentialPrompt(text)) {
        result.needsCredentials = true;
        result.state = "needsCredentials";
        return result;
    }

    // Bluetit down, or D-Bus policy refusing this user. Either way not a login problem, so it
    // must never route the user to a login flow that cannot succeed.
    if (/cannot connect to bluetit|bluetit is not running|failed to connect to (the )?(bluetit|d-?bus)|dbus.*(refused|denied)|connection refused/i.test(text)) {
        result.daemonReachable = false;
        return result;
    }
    if (/permission denied|access denied|not authorized|airvpn group/i.test(text)) {
        result.daemonReachable = false;
        return result;
    }

    // Network filter and lock. Independent of connection state and verified in the
    // disconnected fixture.
    var lockMatch = text.match(/network (?:filter and lock|lock)[^\n]*?\b(disabled|enabled|active|inactive|off|on)\b/i);
    if (lockMatch) {
        var lockWord = lockMatch[1].toLowerCase();
        result.networkLockKnown = true;
        result.networkLock = lockWord === "enabled" || lockWord === "active" || lockWord === "on";
    }

    // "not connected" is tested first. It does not contain the "bluetit is connected"
    // phrase, but ordering makes the intent unmistakable to the next reader.
    if (/bluetit is not connected/i.test(text)) {
        result.state = "disconnected";
        return result;
    }
    if (/bluetit is (?:now )?connecting/i.test(text)) {          // UNVERIFIED
        result.state = "connecting";
        return result;
    }
    if (/bluetit is disconnecting/i.test(text)) {                 // UNVERIFIED
        result.state = "disconnecting";
        return result;
    }
    if (/bluetit is (?:now )?connected|connected to airvpn server/i.test(text)) {
        result.state = "connected";
        Object.assign(result, parseConnectionDetail(output, lines));
        return result;
    }

    // Unrecognized. Surface what it actually said so the panel is never a bare "Error" with
    // no detail, and so the next person capturing a connected fixture has the raw phrasing.
    var meaningful = lines.filter(function (line) { return !/^network (filter and lock|lock)/i.test(line); });
    if (meaningful.length > 0)
        result.unknownStatus = meaningful[meaningful.length - 1].trim();
    else if (Number(exitCode) !== 0 && Number(exitCode) !== undefined)
        result.unknownStatus = "goldcrest exited " + Number(exitCode);

    return result;
}

// Deliberately NOT surfaced: the assigned/exit IP. Dropped at the parser boundary exactly as
// nordvpn-parse.js does, so no property downstream could leak it into a log or a screenshot
// of a public repo.
function parseConnectionDetail(output, lines) {
    var values = labelMap(output);
    var detail = {
        country: values.country ?? "",
        server: values.server ?? values["server name"] ?? "",
        technology: normalizeVpnType(values["vpn type"] ?? values.type ?? values.protocol ?? "")
    };

    if (detail.server === "") {
        for (var i = 0; i < lines.length; i++) {
            var match = lines[i].match(/connected to airvpn server\s+([^\s(,]+)\s*\(([^)]+)\)/i);
            if (match) {
                detail.server = match[1];
                var locationParts = match[2].split(",");
                detail.country = locationParts[locationParts.length - 1].trim();
                break;
            }
            match = lines[i].match(/bluetit is (?:now )?connected to ([^\s,]+)/i);
            if (match) {
                detail.server = match[1];
                break;
            }
        }
    }

    if (detail.technology === "") {
        if (/wireguard/i.test(String(output ?? "")))
            detail.technology = "WireGuard";
        else if (/openvpn/i.test(String(output ?? "")))
            detail.technology = "OpenVPN";
    }

    return detail;
}

// Canonical casing for the two Goldcrest accepts on --air-vpn-type. Anything unrecognized is
// returned trimmed rather than forced, so an added type shows through instead of vanishing.
function normalizeVpnType(value) {
    var normalized = String(value ?? "").trim().toLowerCase();
    if (/^wireguard\b/.test(normalized))
        return "WireGuard";
    if (/^openvpn\b/.test(normalized))
        return "OpenVPN";
    return String(value ?? "").trim();
}

// The CLI argument form, which is lowercase. Anything that is not "openvpn" means WireGuard,
// per plan §2: compared this way so a typo or a stale config value cannot flip the default
// away from the Suite's own default.
function vpnTypeArgument(value) {
    return String(value ?? "").trim().toLowerCase() === "openvpn" ? "openvpn" : "wireguard";
}

// ------------------------------------------------------------------------ country list

// The country table is fixed-width and the widths are declared by its own rule line:
//
//     ISO Code Name                           Servers Users Bandwidth    Max BW    Load
//     -------- ------------------------------ ------- ----- ------------ ---------- ----
//     AT       Austria                              3   487  3.87 Gbit/s 6.00 Gbit/s  64%
//
// Slicing by those spans is the only robust option: names contain spaces and parentheses
// ("Republic of China (Taiwan)"), so whitespace splitting cannot work.
//
// Bandwidth / Max BW are NOT sliced - their values overflow the declared column width
// ("6.00 Gbit/s" in a 10-wide field), and v1 has no use for them. Load is taken with a
// trailing percent match, which is width-independent.
function columnSpans(ruleLine) {
    var spans = [];
    var pattern = /-+/g;
    var match;
    while ((match = pattern.exec(String(ruleLine ?? ""))) !== null)
        spans.push([match.index, match.index + match[0].length]);
    return spans;
}

function parseCountryList(output) {
    var text = stripTimestamps(output);
    var lines = contentLines(output);

    var result = { countries: [], error: "", needsCredentials: false, declaredCount: -1 };

    if (detectsCredentialPrompt(text)) {
        result.needsCredentials = true;
        return result;
    }

    // Goldcrest reports a bad pattern on stdout with exit 1, e.g.
    // "ERROR: AirVPN country not found" (air-list-country-notfound.txt).
    var errorMatch = text.match(/^\s*ERROR:\s*(.+)$/im);
    if (errorMatch) {
        result.error = errorMatch[1].trim();
        return result;
    }

    // "** AirVPN Country List (23) **" - kept so a truncated read can be detected rather
    // than silently yielding a short list.
    var headerMatch = text.match(/AirVPN Country List \((\d+)\)/i);
    if (headerMatch)
        result.declaredCount = Number(headerMatch[1]);

    var ruleIndex = -1;
    for (var i = 0; i < lines.length; i++) {
        // The rule line is dashes and spaces only, and long enough to be a real table rule.
        if (/^-[- ]*-$/.test(lines[i]) && lines[i].replace(/[^-]/g, "").length >= 8) {
            ruleIndex = i;
            break;
        }
    }
    if (ruleIndex < 0)
        return result;

    var spans = columnSpans(lines[ruleIndex]);
    if (spans.length < 2)
        return result;

    var seen = {};
    for (var row = ruleIndex + 1; row < lines.length; row++) {
        var line = lines[row];
        if (isBoilerplate(line))
            continue;

        var code = line.slice(spans[0][0], spans[0][1]).trim().toUpperCase();
        var name = line.slice(spans[1][0], spans[1][1]).trim();

        // ISO alpha-2 is the row's identity. Anything else is a stray banner or a footer,
        // not a country - the same guard parseList() applies for NordVPN.
        if (!/^[A-Z]{2}$/.test(code) || name === "")
            continue;
        if (seen[code])
            continue;
        seen[code] = true;

        var servers = spans.length > 2
            ? parseInt(line.slice(spans[2][0], spans[2][1]).trim(), 10) : NaN;
        var users = spans.length > 3
            ? parseInt(line.slice(spans[3][0], spans[3][1]).trim(), 10) : NaN;
        var loadMatch = line.match(/(\d+)%\s*$/);

        result.countries.push({
            code: code,
            name: name,
            servers: isNaN(servers) ? 0 : servers,
            users: isNaN(users) ? 0 : users,
            load: loadMatch ? Number(loadMatch[1]) : -1
        });
    }

    return result;
}

// ---------------------------------------------------------------------------- key list

// UNVERIFIED - `--air-key-list` needs an authenticated account, and unauthenticated it is one
// of the two prompt-loop hazards. The service must not call this unless credentials exist.
// Parsed defensively: a name-shaped token per line, boilerplate and prompts rejected.
function parseKeyList(output) {
    var text = stripTimestamps(output);
    if (detectsCredentialPrompt(text))
        return { keys: [], needsCredentials: true };

    var keys = contentLines(output)
        .filter(function (line) { return !isBoilerplate(line); })
        .map(function (line) { return line.trim(); })
        .filter(function (line) {
            // Drop table furniture, headers, and prose. AirVPN key names are short tokens
            // (the default is "Default").
            if (/^name$/i.test(line) || /^[-* ]+$/.test(line)
                    || /:/.test(line) || /\s{2,}/.test(line))
                return false;
            return /^[A-Za-z0-9_.\-]{1,64}$/.test(line);
        });

    var unique = [];
    keys.forEach(function (key) {
        if (unique.indexOf(key) < 0)
            unique.push(key);
    });

    return { keys: unique, needsCredentials: false };
}

// ------------------------------------------------------------------------ connect argv

// The ONLY place a connect command line is built, so plan §9's two hard rules are
// structurally guaranteed rather than remembered at each call site:
//   - --async is always present. Without it goldcrest holds the foreground for the life of
//     the tunnel, and Bluetit is the thing that actually owns it.
//   - --network-lock defaults to off. Enabling it on Bostrom can drop Tailscale and SSH,
//     which is our only remote access to the machine.
// lab/test-airvpn-parse.sh asserts both against every option combination.
function buildConnectArgv(options) {
    var opts = options ?? {};
    var argv = ["goldcrest", "--air-connect", "--async"];

    // In asynchronous mode Goldcrest expresses LAN access as the lock mode itself:
    // `on` keeps private networks reachable, `noprivate` blocks them too. The separate
    // --allow-private-network help entry is not documented as taking an on/off value.
    argv.push("--network-lock", opts.networkLock === true
        ? (opts.allowPrivateNetwork === false ? "noprivate" : "on") : "off");

    if (String(opts.vpnType ?? "") !== "")
        argv.push("--air-vpn-type", vpnTypeArgument(opts.vpnType));

    var tlsMode = String(opts.tlsMode ?? "").trim().toLowerCase();
    if (vpnTypeArgument(opts.vpnType) === "openvpn"
            && (tlsMode === "auth" || tlsMode === "crypt"))
        argv.push("--air-tls-mode", tlsMode);

    argv.push("--air-ipv6", opts.ipv6 === false ? "off" : "on");
    if (opts.useAirVpnDns === false)
        argv.push("--ignore-dns-push");

    var key = String(opts.key ?? "").trim();
    if (key !== "")
        argv.push("--air-key", key);

    // Country OR server, never both: --air-server pins one host and --air-country would then
    // be ignored, which reads to the user as the widget having lost their pick.
    var server = String(opts.server ?? "").trim();
    var country = String(opts.country ?? "").trim();
    if (server !== "")
        argv.push("--air-server", server);
    else if (country !== "")
        argv.push("--air-country", country);

    // Never --air-user / --air-password. Credentials live only in ~/.config/goldcrest.rc at
    // 0600; a password on argv is world-readable in /proc for the life of the process.
    return argv;
}

// ---------------------------------------------------------------------------- flags

// AirVPN prints ISO alpha-2 natively, so there is no token->code map to maintain (the reason
// nordvpn-iso.js exists). Regional-indicator pair, or "" so the UI falls back to a badge.
function flagFor(code) {
    var normalized = String(code ?? "").trim().toUpperCase();
    if (!/^[A-Z]{2}$/.test(normalized))
        return "";
    return String.fromCodePoint(0x1F1E6 + normalized.charCodeAt(0) - 65)
        + String.fromCodePoint(0x1F1E6 + normalized.charCodeAt(1) - 65);
}
