import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Banked-resets / usage-page row. One button: quiet text link normally,
// filled only when resets are actually banked. The resets line shows
// only when banked (type and expiry when present); "No resets" stays
// quiet/omitted. Always stacked (link below the text): deterministic
// at any card width, from a narrow desktop widget to a wide dash card.
Column {
    id: root

    property var provider: null
    property double nowMs: Date.now()
    property var onOpenUsage: null

    AiUsageShared {
        id: u
    }

    readonly property bool banked: (root.provider?.resets?.available ?? 0) > 0
    readonly property bool hasLink: u.providerLink(root.provider) !== ""
    readonly property string resetsText: u.resetsLine(root.provider, root.nowMs)

    spacing: Math.max(Theme.spacingXXS, Theme.spacingXS + Theme.densityStepXS)
    visible: !!root.provider && (root.banked || root.hasLink)

    StyledText {
        visible: root.resetsText !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.resetsText
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    DButton {
        visible: root.banked || root.hasLink
        variant: root.banked ? "filled" : "text"
        text: "Open usage page"
        iconName: "open_in_new"
        onClicked: {
            var url = u.providerLink(root.provider);
            if (url)
                Qt.openUrlExternally(url);
            if (root.onOpenUsage && typeof root.onOpenUsage === "function")
                root.onOpenUsage();
        }
    }
}
