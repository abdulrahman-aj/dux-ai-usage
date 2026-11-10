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
    readonly property bool showClaude: cardSettings.enableClaude ?? true
    readonly property bool showCodex: cardSettings.enableCodex ?? true
    readonly property bool showGo: cardSettings.enableGo ?? true

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

    readonly property var providers: {
        var all = snapshot?.providers ?? [];
        return all.filter(p => (p.id === "claude" && root.showClaude) || (p.id === "codex" && root.showCodex) || (p.id === "opencodeGo" && root.showGo));
    }

    Row {
        anchors.centerIn: parent
        spacing: Theme.spacingM

        Repeater {
            model: root.providers
            delegate: Row {
                property var provider: modelData
                readonly property var headline: u.headlineWindow(provider, root.warnAt, root.critAt)
                readonly property string level: u.headlineLevel(provider, root.warnAt, root.critAt)

                spacing: Theme.spacingXS

                DSVGIcon {
                    source: u.logoFor(provider?.id)
                    size: 18
                    colorOverride: u.stateColor(level)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: provider?.error ? "–" : u.pctText(headline?.usedPercent)
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    color: u.stateColor(level)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: u.isShortTakeover(provider) && !provider?.error
                    text: u.shortMark(headline?.id)
                    font.pixelSize: Theme.fontSizeSmall
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
