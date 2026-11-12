import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One provider card: logo, name and plan in the header with the usage
// page as a small icon button, then one meter per window and any
// notes. Built on Dux's own DCard (outlined surface, theme tones), so it
// looks like the cards in Dux's battery popout and Dash. The parent sets
// width; a stacked list sets first/last so the cards form one grouped
// list (Dux's grouped-list radii), otherwise every corner is rounded.
DCard {
    id: root

    property var provider: null
    property double nowMs: Date.now()
    property real warnAt: 80
    property real critAt: 100
    property var onOpenUsage: null
    property real outerRadius: Theme.cornerRadius
    property bool first: true
    property bool last: true

    AiUsageShared {
        id: u
    }

    readonly property var tc: u.clampedThresholds(root.warnAt, root.critAt)
    readonly property string updatedLine: u.providerUpdatedText(root.provider, root.nowMs)
    readonly property string resetsLine: u.resetsLine(root.provider, root.nowMs)
    readonly property string usageLink: u.providerLink(root.provider)
    readonly property real startRadius: first ? outerRadius : Theme.groupedListInnerRadius
    readonly property real endRadius: last ? outerRadius : Theme.groupedListInnerRadius

    pad: u.cardPad
    restRadius: outerRadius
    topLeftRadius: startRadius
    topRightRadius: startRadius
    bottomLeftRadius: endRadius
    bottomRightRadius: endRadius
    implicitHeight: body.implicitHeight + pad * 2

    Column {
        id: body
        width: parent.width
        spacing: u.rowGap

        Item {
            width: parent.width
            height: Math.max(nameText.implicitHeight, openBtn.visible ? openBtn.height : 0)

            DSVGIcon {
                id: logoIcon
                source: u.logoFor(root.provider?.id)
                size: Theme.iconSizeSmall
                colorOverride: root.contentColor
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
                color: root.contentColor
            }

            StyledText {
                anchors.left: nameText.right
                anchors.leftMargin: Theme.spacingXS
                anchors.right: openBtn.visible ? openBtn.left : parent.right
                anchors.rightMargin: openBtn.visible ? Theme.spacingXS : 0
                anchors.baseline: nameText.baseline
                visible: !!(root.provider?.plan)
                elide: Text.ElideRight
                text: root.provider?.plan ?? ""
                font.pixelSize: Theme.fontSizeSmall
                color: root.mutedColor
            }

            // Icon-sized button (Dux's in-row action pattern): the header
            // stays one text line tall instead of a 32px button row.
            DActionButton {
                id: openBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.usageLink !== ""
                buttonSize: Theme.iconSizeMedium + Theme.spacingXS
                iconSize: Theme.iconSizeSmall
                iconColor: root.mutedColor
                iconName: "open_in_new"
                tooltipText: "Open usage page"
                onClicked: {
                    Qt.openUrlExternally(root.usageLink);
                    if (root.onOpenUsage && typeof root.onOpenUsage === "function")
                        root.onOpenUsage();
                }
            }
        }

        StyledText {
            visible: root.updatedLine !== ""
            width: parent.width
            elide: Text.ElideRight
            text: root.updatedLine
            font.pixelSize: Theme.fontSizeSmall
            color: root.mutedColor
        }

        StyledText {
            visible: !!(root.provider?.error)
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.provider?.error?.hint ?? ""
            font.pixelSize: Theme.fontSizeSmall
            color: root.mutedColor
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

        StyledText {
            visible: root.resetsLine !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.resetsLine
            font.pixelSize: Theme.fontSizeSmall
            color: root.mutedColor
        }
    }
}
