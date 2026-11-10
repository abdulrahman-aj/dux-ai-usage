import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One provider card: logo + name + plan, big headline percentage,
// per-window gauges with reset countdowns, resets/usage row. Used by
// the dash tab grid and the desktop widget alike (same component,
// sized by its rectangle); the parent sets width, the card wraps or
// stacks responsively via the shared flow columns.
StyledRect {
    id: root

    property var provider: null
    property double nowMs: Date.now()
    property string fetchedAt: ""
    property real warnAt: 80
    property real critAt: 100

    AiUsageShared {
        id: u
    }

    readonly property var headline: u.headlineWindow(root.provider, root.warnAt, root.critAt)
    readonly property string headlineLevel: u.headlineLevel(root.provider, root.warnAt, root.critAt)
    readonly property color headlineColor: u.stateColor(root.headlineLevel)

    color: Theme.cardSurface ?? Theme.surfaceContainerHigh
    radius: Theme.cornerRadius

    implicitHeight: body.implicitHeight + Theme.spacingM * 2

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        Item {
            id: headerRow
            width: parent.width
            height: Math.max(logoIcon.implicitHeight, nameText.implicitHeight, planText.implicitHeight, staleText.implicitHeight)

            DSVGIcon {
                id: logoIcon
                source: u.logoFor(root.provider?.id)
                size: 18
                colorOverride: root.headlineColor
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                id: nameText
                anchors.left: logoIcon.right
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: root.provider?.name ?? ""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            StyledText {
                id: staleText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: u.staleText(root.provider, root.fetchedAt, root.nowMs)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }

            StyledText {
                id: planText
                anchors.left: nameText.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: staleText.left
                anchors.rightMargin: staleText.visible ? Theme.spacingS : 0
                anchors.verticalCenter: parent.verticalCenter
                visible: !!(root.provider?.plan)
                elide: Text.ElideRight
                text: root.provider?.plan ?? ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        Row {
            spacing: Theme.spacingXS

            StyledText {
                text: root.provider?.error ? "–" : u.pctText(root.headline?.usedPercent)
                font.pixelSize: Theme.fontSizeLarge + 8
                font.weight: Theme.fontWeightMedium
                color: root.headlineColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: u.isShortTakeover(root.provider) && !root.provider?.error
                text: u.shortMark(root.headline?.id)
                font.pixelSize: Theme.fontSizeSmall
                color: root.headlineColor
                opacity: 0.85
                anchors.top: parent.top
                anchors.topMargin: 2
            }

            StyledText {
                visible: !!(root.headline?.label) && !root.provider?.error
                text: root.headline?.label ?? ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
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

            WindowRow {
                width: parent.width
                win: modelData
                nowMs: root.nowMs
                warnAt: root.warnAt
                critAt: root.critAt
            }
        }

        UsageRow {
            width: parent.width
            provider: root.provider
        }
    }
}
