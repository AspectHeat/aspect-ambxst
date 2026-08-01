import QtQuick
import "nordvpn-iso.js" as Iso

// One NordVPN country. Follows the TailscalePeer.qml contract: a plain QtObject whose
// presentational properties are all bindings off a single ingest slot, so the service can
// reassign `token` and every derived value re-evaluates without an update method.
//
// No Process, no Config, no methods - the service owns all I/O.
QtObject {
    id: root

    // The CLI token exactly as `nordvpn countries` printed it, e.g. "United_States".
    // This is also a valid `nordvpn connect` argument, so it is kept verbatim.
    property string token: ""

    // Cities are fetched lazily, only when a row is expanded, because each one costs a
    // separate CLI invocation. `citiesLoaded` distinguishes "not fetched yet" from
    // "fetched and genuinely empty", which the UI renders differently.
    property list<var> cities: []
    property bool citiesLoaded: false
    property bool citiesLoading: false

    readonly property string code: Iso.codeFor(root.token)
    readonly property string name: Iso.displayName(root.token)

    // "" when the ISO code is unknown or the font lacks the glyph pair, so the UI can fall
    // back to `badge` instead of rendering tofu.
    readonly property string flag: Iso.flagFor(root.code)
    readonly property bool hasFlag: root.flag !== ""
    readonly property string badge: root.code !== "" ? root.code : "??"

    readonly property int cityCount: root.cities.length

    // Precomputed so filtering a 149-row list does not rebuild these per keystroke.
    // Matches display name, CLI token, and ISO code per plan §6.
    readonly property string searchKey:
        (root.name + " " + root.token + " " + root.code).toLowerCase()

    // `nordvpn status` prints a human country name ("United States"), whereas `token` is the
    // underscore form and `name` may be a friendlier override ("Laos" for
    // Lao_Peoples_Democratic_Republic, "Côte d'Ivoire" for Cote_Divoire). Comparing status
    // output against `name` alone silently fails for all 8 overridden or oddly-cased
    // countries, so the connected badge would never appear for them. Compare against every
    // spelling we know, case-insensitively.
    function matchesStatusName(value): bool {
        const needle = String(value ?? "").trim().toLowerCase();
        if (needle === "")
            return false;
        return needle === root.name.toLowerCase()
            || needle === root.token.toLowerCase()
            || needle === root.token.replace(/_/g, " ").toLowerCase();
    }
}
