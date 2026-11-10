import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

// Desktop widget: same data as the popout, sized by the user.
// Per-instance options (layer, screens) are handled by the shell;
// settings here come from the plugin settings like every surface.
DesktopPluginComponent {
    id: root

    minWidth: 220
    minHeight: 160

    readonly property real warnAt: pluginData.warnThreshold ?? 80
    readonly property real critAt: pluginData.critThreshold ?? 100
    readonly property bool showClaude: pluginData.enableClaude ?? true
    readonly property bool showCodex: pluginData.enableCodex ?? true
    readonly property bool showGo: pluginData.enableGo ?? true

    PluginGlobalVar {
        id: snapshotVar
        varName: "duxAiSnapshot"
        defaultValue: null
    }

    readonly property var providers: {
        var all = snapshotVar.value?.providers ?? [];
        return all.filter(p => (p.id === "claude" && root.showClaude) || (p.id === "codex" && root.showCodex) || (p.id === "opencodeGo" && root.showGo));
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.cardSurface ?? Theme.surfaceContainerHigh
        opacity: 0.92
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM

        StyledText {
            text: "AI Usage"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        Repeater {
            model: root.providers
            delegate: ProviderSection {
                provider: modelData
                warn: root.warnAt
                crit: root.critAt
                barWidth: 110
                openUrl: url => Qt.openUrlExternally(url)
            }
        }

        StyledText {
            visible: root.providers.length === 0
            text: "Waiting for first poll…"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }
}
