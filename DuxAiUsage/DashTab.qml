import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import qs.Modules.Plugins

// Roomy provider cards in a grid: one card per provider, filling the
// tab width (cards wrap when narrow). Same ProviderCard component as
// the desktop widget.
DashTabComponent {
    id: root

    property double headerNowMs: Date.now()

    Timer {
        interval: 60000
        repeat: true
        running: root.live
        onTriggered: root.headerNowMs = Date.now()
    }

    readonly property real warnAt: pluginData.warnThreshold ?? 80
    readonly property real critAt: pluginData.critThreshold ?? 100

    AiUsageShared {
        id: u
    }

    PluginGlobalVar {
        id: snapshotVar
        varName: "duxAiSnapshot"
        defaultValue: null
    }

    PluginGlobalVar {
        id: refreshVar
        varName: "duxAiRefresh"
        defaultValue: 0
    }

    readonly property var snapshot: snapshotVar.value
    readonly property var providers: u.visibleProviders(root.snapshot, root.pluginData)

    // Showing the AI Usage Dash tab refreshes due providers, same as the popout.
    onLiveChanged: {
        if (live)
            refreshVar.set((refreshVar.value ?? 0) + 1);
    }

    // The Dash host already pads the tab (DashMetrics.contentPadding);
    // gaps follow Dash's own density-aware grid gap.
    readonly property real gapM: DashMetrics.contentGap

    // Report the NATURAL content height (cards at their own size), never
    // the stretched one: the panel height derives from this, so a
    // stretched value would pin the panel and stop it ever shrinking.
    // Plugin tabs default to five panel rows; seed ours to the minimum
    // once so the panel tracks content height instead (user resizes
    // still persist and win after that).
    implicitHeight: root.providers.length > 0 ? headerRow.height + gapM + cardFlow.naturalHeight : content.implicitHeight
    menuActions: [
        {
            label: "Refresh now",
            iconName: "refresh",
            action: () => refreshVar.set((refreshVar.value ?? 0) + 1)
        }
    ]

    Component.onCompleted: seedCompactPanel()
    onEntryIdChanged: seedCompactPanel()
    onPluginServiceChanged: seedCompactPanel()

    // The host injects entryId/pluginService after load, so the seed
    // retries until both are present. The marker lives in plugin
    // settings (not in the absence of stored rows): the shell's "Reset
    // panel size" clears stored rows, and must not re-trigger the seed.
    function seedCompactPanel() {
        if (!root.entryId || !root.pluginService || !root.pluginId)
            return;
        if (root.getData("panelRowsSeeded", false))
            return;
        if (!("panelRows" in DashRegistry.storedOptions(root.entryId)))
            DashRegistry.setOptions(root.entryId, {"panelRows": DashMetrics.minimumTabRows});
        root.setData("panelRowsSeeded", true);
    }

    Column {
        id: content
        width: parent.width
        spacing: gapM

        // No title: the Dash tab bar already names the tab.
        Row {
            id: headerRow
            width: parent.width
            spacing: Theme.spacingXS

            StyledText {
                text: u.updatedText(root.snapshot?.fetchedAt, root.headerNowMs)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            DActionButton {
                iconName: "refresh"
                tooltipText: "Refresh now"
                buttonSize: Theme.iconSizeMedium + Theme.spacingXS
                iconSize: Theme.iconSizeSmall
                anchors.verticalCenter: parent.verticalCenter
                onClicked: refreshVar.set((refreshVar.value ?? 0) + 1)
            }
        }

        Flow {
            id: cardFlow
            width: parent.width
            spacing: gapM

            // Breakpoints follow density: denser fits more columns sooner.
            readonly property int cols: width < 460 + Theme.densityStepM ? 1 : width < 760 + Theme.densityStepM ? 2 : 3
            readonly property real cardWidth: (width - (cols - 1) * spacing) / cols

            // The Dash snaps every panel to whole 96px grid rows (two at
            // least, and the rows ignore density), so the panel is almost
            // always taller than the cards and the plugin cannot shrink
            // it. Instead the cards fill it: every card gets the same
            // height, the tallest card's or an equal share of the
            // panel's leftover height, whichever is larger, so the cards
            // end on the panel's bottom edge at every density and size.
            readonly property int rows: Math.ceil(cardRepeater.count / cols)
            readonly property real tallest: {
                var h = 0;
                for (var i = 0; i < cardRepeater.count; i++) {
                    var card = cardRepeater.itemAt(i);
                    if (card)
                        h = Math.max(h, card.implicitHeight);
                }
                return h;
            }
            readonly property real naturalHeight: rows * tallest + Math.max(0, rows - 1) * spacing
            readonly property real fillHeight: root.height - headerRow.height - gapM
            readonly property real cardHeight: rows > 0 ? (Math.max(naturalHeight, fillHeight) - (rows - 1) * spacing) / rows : 0

            Repeater {
                id: cardRepeater
                model: root.providers
                delegate: ProviderCard {
                    width: cardFlow.cardWidth
                    height: cardFlow.cardHeight
                    outerRadius: DashMetrics.cardRadius
                    provider: modelData
                    nowMs: root.headerNowMs
                    warnAt: root.warnAt
                    critAt: root.critAt
                    onOpenUsage: function() {
                        var host = root.dashHost;
                        if (host && typeof host.close === "function")
                            host.close();
                        else if (host)
                            host.dashVisible = false;
                    }
                }
            }
        }

        StyledText {
            visible: root.providers.length === 0
            text: root.snapshot ? "All providers are disabled in settings." : "Waiting for the first poll (up to a few minutes after enabling)…"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
        }
    }
}
