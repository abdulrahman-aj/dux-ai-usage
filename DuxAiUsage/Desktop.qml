import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
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

    // Inline formatting helpers (see Widget.qml): shared QML includes
    // stay frozen at shell startup, so per-surface formatting lives here.
    function worstOf(provider) {
        var worst = null;
        var windows = provider?.windows ?? [];
        for (var i = 0; i < windows.length; i++) {
            var pct = windows[i].usedPercent;
            if (pct === null || pct === undefined)
                continue;
            if (!worst || pct > worst.usedPercent)
                worst = windows[i];
        }
        return worst;
    }

    // Inline formatting helpers (see Widget.qml).
    function shortWindow(windowId) {
        var known = {"fiveHour": "5h", "rolling": "5h", "weekly": "W",
                     "monthly": "M", "weekly-fable": "F"};
        if (known[windowId])
            return known[windowId];
        var parts = String(windowId).split(/[^a-zA-Z0-9]+/);
        if (parts.length === 1 && parts[0].length > 1)
            return (parts[0][0] + parts[0][1]).toUpperCase();
        var code = "";
        for (var i = 0; i < parts.length && code.length < 2; i++) {
            if (parts[i].length > 0)
                code += parts[i][0].toUpperCase();
        }
        return code || windowId;
    }

    function worstText(provider) {
        if (provider?.error)
            return "–";
        var worst = worstOf(provider);
        if (!worst)
            return "…";
        var names = {"claude": "Cl", "codex": "Cx", "opencodeGo": "Go"};
        return (names[provider.id] ?? provider.id) + " " + shortWindow(worst.id) + " " + Math.round(worst.usedPercent) + "%";
    }

    function worstLevel(provider) {
        if (provider?.error)
            return "unknown";
        var worst = worstOf(provider);
        if (!worst)
            return "unknown";
        if (worst.usedPercent >= root.critAt)
            return "crit";
        if (worst.usedPercent >= root.warnAt)
            return "warn";
        return "ok";
    }

    function worstColor(provider) {
        var level = worstLevel(provider);
        if (level === "crit")
            return Theme.error;
        if (level === "warn")
            return Theme.warning;
        return Theme.surfaceText;
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
            delegate: StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: root.worstText(modelData)
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: root.worstColor(modelData)
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
