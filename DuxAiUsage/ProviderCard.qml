import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One provider card: logo + name + plan, big headline percentage,
// per-window gauges with reset countdowns, resets/usage row. Used by
// the dash tab grid and the desktop widget alike (same component,
// sized by its rectangle); the parent sets width, the host lays cards
// out in its own flow grid.
StyledRect {
    id: root

    property var provider: null
    property double nowMs: Date.now()
    property string fetchedAt: ""
    property real warnAt: 80
    property real critAt: 100
    property var onOpenUsage: null

    AiUsageShared {
        id: u
    }

    readonly property var headline: u.headlineWindow(root.provider)
    readonly property string headlineLevel: u.headlineLevel(root.provider, tc[0], tc[1])
    readonly property color headlineColor: u.stateColor(root.headlineLevel)
    readonly property var tc: u.clampedThresholds(root.warnAt, root.critAt)

    color: Theme.cardSurface ?? Theme.surfaceContainerHigh
    radius: Theme.cornerRadius

    // Card padding follows density like Dash contentPadding.
    readonly property real pad: Theme.spacingM + Theme.densityStepXS
    readonly property real gapS: Math.max(Theme.spacingXS, Theme.spacingS + Theme.densityStepXS)

    implicitHeight: body.implicitHeight + pad * 2

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: pad
        spacing: gapS

        Item {
            id: headerRow
            width: parent.width
            height: Math.max(logoIcon.implicitHeight, nameText.implicitHeight, planText.implicitHeight, updatedText.implicitHeight)

            DSVGIcon {
                id: logoIcon
                source: u.logoFor(root.provider?.id)
                size: Math.max(Theme.iconSizeSmall, Theme.iconSizeSmall + Theme.spacingXXS + Theme.densityStepXS)
                colorOverride: Theme.surfaceText
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
                id: updatedText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                // The rate-limit note is the longest header text; cap it
                // so a narrow card elides instead of squeezing the name.
                width: Math.min(implicitWidth, parent.width * 0.6)
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                horizontalAlignment: Text.AlignRight
                text: u.providerUpdatedText(root.provider, root.nowMs)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                id: planText
                anchors.left: nameText.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: updatedText.left
                anchors.rightMargin: updatedText.visible ? root.gapS : 0
                anchors.verticalCenter: parent.verticalCenter
                visible: !!(root.provider?.plan)
                elide: Text.ElideRight
                text: root.provider?.plan ?? ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        Row {
            spacing: gapS

            StyledText {
                text: u.pctText(root.headline?.usedPercent)
                font.pixelSize: Theme.fontSizeLarge + Theme.spacingS
                font.weight: Theme.fontWeightMedium
                color: root.headlineColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.provider?.headlineShort === true
                text: u.shortMark(root.headline?.id)
                font.pixelSize: Theme.fontSizeSmall
                color: root.headlineColor
                opacity: 0.85
                anchors.top: parent.top
                anchors.topMargin: Theme.spacingXXS
            }

            StyledText {
                visible: !!(root.headline?.label)
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
                warnAt: root.tc[0]
                critAt: root.tc[1]
            }
        }

        UsageRow {
            width: parent.width
            provider: root.provider
            nowMs: root.nowMs
            onOpenUsage: root.onOpenUsage
        }
    }
}
