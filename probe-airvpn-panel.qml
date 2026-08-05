import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.widgets.dashboard.controls

// Headless type-resolution and binding check for the AirVPN UI. Run it, do not import it.
//
//   cd ~/Projects/aspect-ambxst
//   QT_QPA_PLATFORM=offscreen qs -p probe-airvpn-panel.qml
//
// Companion to probe-airvpn.qml, which covers the service. This one instantiates the actual
// panel components so that QML type registration, property names, and every binding in them are
// evaluated - which is what catches the "<NewType> is not a type" failure mode from CLAUDE.md
// gotcha 8, plus ReferenceErrors and misspelled properties that qmllint passes silently.
//
// The components are Items rather than windows, so they instantiate fine under a ShellRoot that
// declares no PanelWindow. Layout and painting are NOT verified here - only that everything
// resolves and no binding throws. Give them an explicit size so width-dependent bindings
// (contentWidth, elide, the ListView delegates) actually evaluate rather than short-circuiting
// on a zero width.
ShellRoot {
    id: root

    property int errorCount: 0

    Item {
        id: stage

        width: 520
        height: 900

        // The provider hub, which also exercises the new third card and its Loader. Loaders are
        // active:true, so all three provider pages get compiled here too.
        VpnPanel {
            id: hub

            anchors.fill: parent
            maxContentWidth: 480
        }
    }

    Item {
        id: pageStage

        width: 520
        height: 900

        // The page on its own as well, so a failure is attributable to the page rather than to
        // the hub's Loader.
        AirVpnPanel {
            id: page

            anchors.fill: parent
            maxContentWidth: 480
            showBackButton: true
        }
    }

    Component.onCompleted: {
        console.log("probe-panel: VpnPanel and AirVpnPanel instantiated");
        console.log("  hub.currentSection      = " + JSON.stringify(hub.currentSection));
        console.log("  hub.contentWidth        = " + hub.contentWidth);
        console.log("  page.contentWidth       = " + page.contentWidth);
        console.log("  page.statusText         = " + JSON.stringify(page.statusText));
        console.log("  page.statusColor        = " + page.statusColor);
        console.log("  page.visibleCountries   = " + page.visibleCountries.length);
    }

    Timer {
        interval: 2500
        repeat: true
        running: true

        property int ticks: 0

        onTriggered: {
            ticks++;
            console.log("---- t=" + (ticks * 2.5) + "s ----");
            console.log("  service state       = " + AirVpnService.state
                + " needsCredentials=" + AirVpnService.needsCredentials);
            console.log("  page.statusText     = " + JSON.stringify(page.statusText));
            console.log("  visibleCountries    = " + page.visibleCountries.length);

            // Exercise the filter, which is the binding most likely to break: it reaches through
            // sortedCountries into each country's precomputed searchKey.
            if (ticks === 2) {
                page.searchText = "swit";
                console.log("  filter 'swit'       = " + page.visibleCountries.length
                    + " -> " + (page.visibleCountries[0]?.name ?? "none"));
                page.searchText = "zz-no-match";
                console.log("  filter 'zz-no-match'= " + page.visibleCountries.length);
                page.searchText = "";
            }

            // Walk the hub through every section so each Loader's item is realized and its
            // onLoaded wiring runs.
            if (ticks === 3) {
                for (const section of ["tailscale", "nordvpn", "airvpn", ""]) {
                    hub.currentSection = section;
                    console.log("  hub section " + JSON.stringify(section)
                        + " -> ok");
                }
            }

            if (ticks >= 4) {
                console.log("probe-panel: done, errorCount=" + root.errorCount);
                Qt.quit();
            }
        }
    }
}
