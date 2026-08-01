.pragma library

// NordVPN CLI country token -> ISO 3166-1 alpha-2.
//
// Built from the live output of `nordvpn countries` on NordVPN 5.2.0, captured in
// lab/fixtures/nordvpn/countries.txt (149 entries). The CLI emits country names with
// underscores for spaces and no ISO codes, so this map is the only way to render a flag.
//
// Pure data and pure functions only: no network, no QML imports, no Config. Verified by
// lab/test-nordvpn-parse.sh, which asserts every token in the fixture has an entry here
// and that no entry is orphaned.
//
// The CLI's own naming is retained as the key exactly as printed. Where a naive
// underscore-to-space conversion would read badly, DISPLAY_OVERRIDES supplies the name a
// user expects to search for.

var CODES = {
    "Afghanistan": "AF",
    "Albania": "AL",
    "Algeria": "DZ",
    "Andorra": "AD",
    "Angola": "AO",
    "Argentina": "AR",
    "Armenia": "AM",
    "Australia": "AU",
    "Austria": "AT",
    "Azerbaijan": "AZ",
    "Bahamas": "BS",
    "Bahrain": "BH",
    "Bangladesh": "BD",
    "Barbados": "BB",
    "Belgium": "BE",
    "Belize": "BZ",
    "Bermuda": "BM",
    "Bhutan": "BT",
    "Bolivia": "BO",
    "Bosnia_And_Herzegovina": "BA",
    "Botswana": "BW",
    "Brazil": "BR",
    "Brunei_Darussalam": "BN",
    "Bulgaria": "BG",
    "Burkina_Faso": "BF",
    "Cambodia": "KH",
    "Cameroon": "CM",
    "Canada": "CA",
    "Cape_Verde": "CV",
    "Cayman_Islands": "KY",
    "Chad": "TD",
    "Chile": "CL",
    "Colombia": "CO",
    "Comoros": "KM",
    "Costa_Rica": "CR",
    "Cote_Divoire": "CI",
    "Croatia": "HR",
    "Cyprus": "CY",
    "Czech_Republic": "CZ",
    "Denmark": "DK",
    "Dominican_Republic": "DO",
    "Ecuador": "EC",
    "Egypt": "EG",
    "El_Salvador": "SV",
    "Estonia": "EE",
    "Ethiopia": "ET",
    "Fiji": "FJ",
    "Finland": "FI",
    "France": "FR",
    "Gambia": "GM",
    "Georgia": "GE",
    "Germany": "DE",
    "Ghana": "GH",
    "Greece": "GR",
    "Greenland": "GL",
    "Guam": "GU",
    "Guatemala": "GT",
    "Honduras": "HN",
    "Hong_Kong": "HK",
    "Hungary": "HU",
    "Iceland": "IS",
    "India": "IN",
    "Indonesia": "ID",
    "Iraq": "IQ",
    "Ireland": "IE",
    "Isle_Of_Man": "IM",
    "Israel": "IL",
    "Italy": "IT",
    "Jamaica": "JM",
    "Japan": "JP",
    "Jersey": "JE",
    "Jordan": "JO",
    "Kazakhstan": "KZ",
    "Kenya": "KE",
    "Kuwait": "KW",
    "Kyrgyzstan": "KG",
    "Lao_Peoples_Democratic_Republic": "LA",
    "Latvia": "LV",
    "Lebanon": "LB",
    "Libyan_Arab_Jamahiriya": "LY",
    "Liechtenstein": "LI",
    "Lithuania": "LT",
    "Luxembourg": "LU",
    "Madagascar": "MG",
    "Malawi": "MW",
    "Malaysia": "MY",
    "Maldives": "MV",
    "Malta": "MT",
    "Mauritania": "MR",
    "Mauritius": "MU",
    "Mexico": "MX",
    "Moldova": "MD",
    "Monaco": "MC",
    "Mongolia": "MN",
    "Montenegro": "ME",
    "Morocco": "MA",
    "Mozambique": "MZ",
    "Myanmar": "MM",
    "Nepal": "NP",
    "Netherlands": "NL",
    "New_Zealand": "NZ",
    "Nigeria": "NG",
    "North_Macedonia": "MK",
    "Norway": "NO",
    "Pakistan": "PK",
    "Panama": "PA",
    "Papua_New_Guinea": "PG",
    "Paraguay": "PY",
    "Peru": "PE",
    "Philippines": "PH",
    "Poland": "PL",
    "Portugal": "PT",
    "Puerto_Rico": "PR",
    "Qatar": "QA",
    "Romania": "RO",
    "Rwanda": "RW",
    "Saint_Lucia": "LC",
    "Senegal": "SN",
    "Serbia": "RS",
    "Sierra_Leone": "SL",
    "Singapore": "SG",
    "Slovakia": "SK",
    "Slovenia": "SI",
    "Somalia": "SO",
    "South_Africa": "ZA",
    "South_Korea": "KR",
    "Spain": "ES",
    "Sri_Lanka": "LK",
    "Suriname": "SR",
    "Sweden": "SE",
    "Switzerland": "CH",
    "Taiwan": "TW",
    "Tajikistan": "TJ",
    "Tanzania": "TZ",
    "Thailand": "TH",
    "Togo": "TG",
    "Trinidad_And_Tobago": "TT",
    "Tunisia": "TN",
    "Turkey": "TR",
    "Ukraine": "UA",
    "United_Arab_Emirates": "AE",
    "United_Kingdom": "GB",
    "United_States": "US",
    "Uruguay": "UY",
    "Uzbekistan": "UZ",
    "Venezuela": "VE",
    "Vietnam": "VN",
    "Yemen": "YE",
    "Zambia": "ZM"
};

// Only where underscore-to-space produces something a user would not search for.
var DISPLAY_OVERRIDES = {
    "Bosnia_And_Herzegovina": "Bosnia & Herzegovina",
    "Brunei_Darussalam": "Brunei",
    "Cote_Divoire": "Côte d'Ivoire",
    "Isle_Of_Man": "Isle of Man",
    "Lao_Peoples_Democratic_Republic": "Laos",
    "Libyan_Arab_Jamahiriya": "Libya",
    "Trinidad_And_Tobago": "Trinidad & Tobago"
};

function codeFor(token) {
    return CODES[String(token ?? "")] ?? "";
}

// "New_Zealand" -> "New Zealand". Applied to cities too, which share the convention
// ("Des_Moines", "Saint_Louis").
function displayName(token) {
    var key = String(token ?? "");
    if (DISPLAY_OVERRIDES[key])
        return DISPLAY_OVERRIDES[key];
    return key.replace(/_/g, " ").trim();
}

// Regional-indicator pair. Returns "" for an unknown code so callers can fall back to an
// ISO badge rather than rendering a tofu glyph.
function flagFor(code) {
    var normalized = String(code ?? "").toUpperCase();
    if (!/^[A-Z]{2}$/.test(normalized))
        return "";
    return String.fromCodePoint(
        127397 + normalized.charCodeAt(0),
        127397 + normalized.charCodeAt(1)
    );
}
