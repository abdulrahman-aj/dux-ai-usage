import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Banked-resets / usage-page row. One button: quiet text link normally,
// filled only when resets are actually banked, so the row never shouts
// "Open usage page" next to "No resets banked". Claude (no banked
// resets) shows just the quiet link to its usage settings page. Always
// stacked (link below the text): deterministic at any card width, from
// a 220px desktop widget to a wide dash card.
Column {
    id: root

    property var provider: null

    AiUsageShared {
        id: u
    }

    readonly property bool banked: (root.provider?.resets?.available ?? 0) > 0
    readonly property bool hasLink: u.providerLink(root.provider) !== ""

    spacing: Theme.spacingXS
    visible: !!root.provider && (root.banked || root.hasLink)

    StyledText {
        visible: !!(root.provider?.resets)
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.banked ? (root.provider.resets.available + (root.provider.resets.available === 1 ? " reset available" : " resets available")) : "No resets banked"
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
        }
    }
}
