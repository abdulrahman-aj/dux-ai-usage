import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins

// Glanceable overview card: monochrome logo + headline number per
// provider (the same PillRow as the bar pill, scaled to fit).
// Click opens the dash tab (clickable + opensTab on the base).
DashCardComponent {
    id: root

    // The overview slot's one-shot load-time injection misses this card
    // (verified live: pluginId/pluginService stay empty), so the card
    // reads the shared snapshot and its settings straight from the
    // singletons instead of the injected props. Same data, same defaults.
    property int settingsRev: 0

    readonly property var cardSettings: {
        settingsRev;
        return SettingsData.getPluginSettingsForPlugin("duxAiUsage");
    }

    readonly property var snapshot: (PluginService.globalVars["duxAiUsage"] || {})["duxAiSnapshot"] ?? null

    readonly property real warnAt: cardSettings.warnThreshold ?? 80
    readonly property real critAt: cardSettings.critThreshold ?? 100
    readonly property var tc: u.clampedThresholds(root.warnAt, root.critAt)

    AiUsageShared {
        id: u
    }

    clickable: true

    Connections {
        target: PluginService
        function onPluginDataChanged(changedId) {
            if (changedId === "duxAiUsage")
                root.settingsRev++;
        }
    }

    readonly property var providers: u.visibleProviders(root.snapshot, root.cardSettings)

    // Shrink the glance entries on narrow cards so three providers fit
    // the minimum card instead of clipping at its edges. 118px ≈ one
    // entry's share (logo + two digits + mark) at full size; the share
    // follows density while spacings use the density-aware row gap, and
    // the 0.62 floor keeps text legible.
    readonly property real entryShare: 118 + Theme.densityStepM
    readonly property real rowGap: Math.max(Theme.spacingXS, Theme.spacingS + Theme.densityStepS)
    readonly property real entryScale: {
        var n = Math.max(1, root.providers.length);
        return Math.max(0.62, Math.min(1, root.width / (n * root.entryShare)));
    }

    Row {
        anchors.centerIn: parent
        spacing: rowGap

        Repeater {
            model: root.providers
            delegate: PillRow {
                provider: modelData
                warnAt: root.tc[0]
                critAt: root.tc[1]
                textSize: Math.round(Theme.fontSizeLarge * root.entryScale)
                logoColor: root.contentColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        StyledText {
            visible: root.providers.length === 0
            anchors.verticalCenter: parent.verticalCenter
            text: "AI …"
            font.pixelSize: Theme.fontSizeLarge
            color: root.contentColor
        }
    }
}
