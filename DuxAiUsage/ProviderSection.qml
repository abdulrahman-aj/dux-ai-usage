import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "Format.js" as Format

// One provider block: windows with bars, banked resets, or a one-line hint.
// Used by the bar popout, the dash tab and the desktop widget.
Column {
    id: root

    property var provider: null
    property real warn: 80
    property real crit: 100
    property real barWidth: 140
    property var openUrl: null

    property int nowMs: Date.now()

    spacing: Theme.spacingS
    width: parent ? parent.width : 0

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
    }

    function levelColor(percent) {
        var level = Format.levelOf(percent, root.warn, root.crit);
        if (level === "crit")
            return Theme.error;
        if (level === "warn")
            return Theme.warning;
        return Theme.primary;
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: root.provider?.name ?? ""
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        StyledText {
            visible: !!(root.provider?.plan)
            text: root.provider?.plan ?? ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            visible: root.provider?.stale === true
            text: "· last-known"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.warning
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StyledText {
        visible: !!(root.provider?.error)
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.provider?.error?.hint ?? ""
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Repeater {
        model: root.provider?.error ? [] : (root.provider?.windows ?? [])

        Row {
            width: root.width
            spacing: Theme.spacingS

            StyledText {
                width: 92
                elide: Text.ElideRight
                text: modelData.label ?? modelData.id
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledRect {
                width: root.barWidth
                height: 8
                radius: 4
                color: Theme.surfaceContainerHigh
                anchors.verticalCenter: parent.verticalCenter

                StyledRect {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Math.min(100, Math.max(0, modelData.usedPercent ?? 0)) / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.levelColor(modelData.usedPercent)
                }
            }

            StyledText {
                text: Format.pctText(modelData.usedPercent)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.levelColor(modelData.usedPercent)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: !!modelData.resetsAt
                text: "↻ " + Format.countdown(modelData.resetsAt, root.nowMs)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Row {
        visible: !!(root.provider && root.provider.resets)
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: (root.provider?.resets?.available ?? 0) > 0 ? (root.provider.resets.available + (root.provider.resets.available === 1 ? " reset available" : " resets available")) : "No resets banked"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }

        DButton {
            text: "Open usage page"
            iconName: "open_in_new"
            onClicked: {
                if (root.openUrl && root.provider?.resets?.url)
                    root.openUrl(root.provider.resets.url);
            }
        }
    }
}
