import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins

// Glanceable overview card: logo + headline number per provider.
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
    // entry's share (logo + two digits + mark) at full size; spacings
    // stay fixed, hence the 0.62 floor keeps text legible.
    readonly property real entryScale: {
        var n = Math.max(1, root.providers.length);
        return Math.max(0.62, Math.min(1, root.width / (n * 118)));
    }

    Row {
        anchors.centerIn: parent
        spacing: Theme.spacingM

        Repeater {
            model: root.providers
            delegate: Row {
                property var provider: modelData
                readonly property var headline: u.headlineWindow(provider, root.tc[0], root.tc[1])
                readonly property string level: u.headlineLevel(provider, root.tc[0], root.tc[1])

                spacing: Theme.spacingXS

                DSVGIcon {
                    source: u.logoFor(provider?.id)
                    size: Math.round(18 * root.entryScale)
                    colorOverride: u.stateColor(level)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: provider?.error ? "–" : u.pctText(headline?.usedPercent)
                    font.pixelSize: Math.round(Theme.fontSizeLarge * root.entryScale)
                    font.weight: Theme.fontWeightMedium
                    color: u.stateColor(level)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: u.isShortTakeover(provider) && !provider?.error
                    text: u.shortMark(headline?.id)
                    font.pixelSize: Math.round(Theme.fontSizeSmall * root.entryScale)
                    color: u.stateColor(level)
                    opacity: 0.85
                    anchors.top: parent.top
                    anchors.topMargin: 2
                }
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
