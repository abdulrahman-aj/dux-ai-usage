import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One bar-pill entry: provider logo + ONE headline number, tinted by
// state. A tiny mark appears only when a short window takes over the
// long default (see model.headline_window). No provider codes, no
// window labels in the normal state.
Row {
    id: root

    property var provider: null
    property real warnAt: 80
    property real critAt: 100
    property real textSize: Theme.fontSizeMedium

    AiUsageShared {
        id: u
    }

    readonly property var headline: u.headlineWindow(root.provider, tc[0], tc[1])
    readonly property string level: u.headlineLevel(root.provider, tc[0], tc[1])
    readonly property color state: u.stateColor(root.level)
    readonly property var tc: u.clampedThresholds(root.warnAt, root.critAt)

    spacing: Theme.spacingXS

    DSVGIcon {
        source: u.logoFor(root.provider?.id)
        size: Math.max(14, Math.round(root.textSize + 2))
        colorOverride: root.state
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        text: root.provider?.error ? "–" : u.pctText(root.headline?.usedPercent)
        font.pixelSize: root.textSize
        font.weight: Theme.fontWeightMedium
        color: root.state
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        visible: u.isShortTakeover(root.provider) && !root.provider?.error
        text: u.shortMark(root.headline?.id)
        font.pixelSize: Math.max(9, Math.round(root.textSize * 0.62))
        color: root.state
        opacity: 0.85
        anchors.top: parent.top
        anchors.topMargin: 1
    }
}
