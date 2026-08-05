import QtQuick
import "airvpn-parse.js" as Parse

// One AirVPN country. Follows the NordVpnCountry.qml / TailscalePeer.qml contract: a plain
// QtObject whose presentational properties are bindings off ingest slots, so the service can
// reassign them and every derived value re-evaluates without an update method.
//
// No Process, no Config, no methods beyond pure matching - the service owns all I/O.
//
// Unlike NordVPN there is no token->ISO map to maintain (the reason nordvpn-iso.js exists):
// `goldcrest --air-list --air-country all` prints ISO alpha-2 natively, and that code is
// itself a valid `--air-country` argument.
QtObject {
    id: root

    // Ingest slots, written by AirVpnService.syncCountries().
    property string code: ""
    property string name: ""
    property int servers: 0
    property int users: 0

    // -1 means the CLI did not report a load figure, which the UI renders as absent rather
    // than as a 0% (idle) bar.
    property int load: -1

    // Named `token` for parity with NordVpnCountry, so the shared panel idioms - favorites,
    // preferredCountry, connect targets - read identically across providers. For AirVPN the
    // stable identity and the connect argument are the same string.
    readonly property string token: root.code

    // "" when the code is unknown or malformed, so the UI falls back to `badge` instead of
    // rendering tofu.
    readonly property string flag: Parse.flagFor(root.code)
    readonly property bool hasFlag: root.flag !== ""
    readonly property string badge: root.code !== "" ? root.code : "??"

    readonly property bool hasLoad: root.load >= 0

    // Precomputed so filtering the list does not rebuild it per keystroke. Matches display
    // name and ISO code - there is no third spelling for AirVPN.
    readonly property string searchKey: (root.name + " " + root.code).toLowerCase()

    // `--bluetit-status` reports a human country name, so the connected badge is matched
    // against every spelling we hold rather than against `name` alone.
    function matchesStatusName(value): bool {
        const needle = String(value ?? "").trim().toLowerCase();
        if (needle === "")
            return false;
        return needle === root.name.toLowerCase() || needle === root.code.toLowerCase();
    }
}
