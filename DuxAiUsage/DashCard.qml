import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins

// Glanceable card: worst window per provider. Click opens the dash tab.
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

    function worstText(provider) {
        var code = shortCode(provider.id, "").provider;
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
        return {"text": code + " " + shortCode(provider.id, worst.id).window + " " + pctText(worst.usedPercent),
                "level": levelOf(worst.usedPercent, root.warnAt, root.critAt)};
    }

    // Inline formatting helpers (see Widget.qml).
    function shortCode(providerId, windowId) {
        var providers = {"claude": "Cl", "codex": "Cx", "opencodeGo": "Go"};
        var windows = {"fiveHour": "5h", "rolling": "5h", "weekly": "W",
                       "monthly": "M", "weekly-fable": "F"};
        return {"provider": providers[providerId] ?? providerId,
                "window": windows[windowId] ?? windowId};
    }

    function pctText(percent) {
        if (percent === null || percent === undefined || isNaN(percent))
            return "–";
        return Math.round(percent) + "%";
    }

    function levelOf(percent, warn, crit) {
        if (percent === null || percent === undefined || isNaN(percent))
            return "unknown";
        if (percent >= crit)
            return "crit";
        if (percent >= warn)
            return "warn";
        return "ok";
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
