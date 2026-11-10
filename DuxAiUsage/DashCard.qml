import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "Format.js" as Format

// Glanceable card: worst window per provider. Click opens the dash tab.
DashCardComponent {
    id: root

    readonly property real warnAt: pluginData.warnThreshold ?? 80
    readonly property real critAt: pluginData.critThreshold ?? 100
    readonly property bool showClaude: pluginData.enableClaude ?? true
    readonly property bool showCodex: pluginData.enableCodex ?? true
    readonly property bool showGo: pluginData.enableGo ?? true

    clickable: true

    PluginGlobalVar {
        id: snapshotVar
        varName: "duxAiSnapshot"
        defaultValue: null
    }

    readonly property var providers: {
        var all = snapshotVar.value?.providers ?? [];
        return all.filter(p => (p.id === "claude" && root.showClaude) || (p.id === "codex" && root.showCodex) || (p.id === "opencodeGo" && root.showGo));
    }

    function worstText(provider) {
        var code = Format.shortCode(provider.id, "").provider;
        if (provider.error)
            return {"text": code + " –", "level": "unknown"};
        var worst = null;
        var windows = provider.windows ?? [];
        for (var i = 0; i < windows.length; i++) {
            var pct = windows[i].usedPercent;
            if (pct === null || pct === undefined)
                continue;
            if (worst === null || pct > worst.usedPercent)
                worst = windows[i];
        }
        if (!worst)
            return {"text": code + " …", "level": "unknown"};
        return {"text": code + " " + Format.shortCode(provider.id, worst.id).window + " " + Format.pctText(worst.usedPercent),
                "level": Format.levelOf(worst.usedPercent, root.warnAt, root.critAt)};
    }

    function levelColor(level) {
        if (level === "crit")
            return Theme.error;
        if (level === "warn")
            return Theme.warning;
        return root.contentColor;
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingXS

        Repeater {
            model: root.providers

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.worstText(modelData).text
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Theme.fontWeightMedium
                color: root.levelColor(root.worstText(modelData).level)
            }
        }

        StyledText {
            visible: root.providers.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            text: "AI …"
            font.pixelSize: Theme.fontSizeLarge
            color: root.contentColor
        }
    }
}
