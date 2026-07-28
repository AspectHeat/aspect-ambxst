import QtQuick

QtObject {
    id: root

    property var lastIpcObject: ({})

    property string nodeId: lastIpcObject.ID ?? ""
    property string hostName: lastIpcObject.HostName ?? ""
    property string dnsName: lastIpcObject.DNSName ?? ""
    property string os: lastIpcObject.OS ?? ""
    property bool online: lastIpcObject.Online ?? false
    property string lastSeen: lastIpcObject.LastSeen ?? ""
    property var addresses: lastIpcObject.TailscaleIPs ?? []
    property bool isExitNode: lastIpcObject.ExitNode ?? false
    property bool exitNodeOption: lastIpcObject.ExitNodeOption ?? false
    property string relay: lastIpcObject.Relay ?? ""

    readonly property string ipv4: addresses.find(address => !address.includes(":")) ?? ""
    readonly property string ipv6: addresses.find(address => address.includes(":")) ?? ""
    readonly property bool isSelf: false
}
