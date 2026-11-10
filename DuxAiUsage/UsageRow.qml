import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Banked-resets / usage-page row. Quiet text link normally; a filled
// button only when resets are actually banked, so the row never shouts
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

    spacing: Theme.spacingXS
    visible: !!root.provider && ((root.provider?.resets?.available ?? 0) > 0 || u.providerLink(root.provider) !== "")

    StyledText {
        visible: !!(root.provider?.resets)
        width: parent.width
        wrapMode: Text.WordWrap
        text: (root.provider?.resets?.available ?? 0) > 0 ? (root.provider.resets.available + (root.provider.resets.available === 1 ? " reset available" : " resets available")) : "No resets banked"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    DButton {
        visible: (root.provider?.resets?.available ?? 0) > 0
        text: "Open usage page"
        iconName: "open_in_new"
        onClicked: {
            var url = u.providerLink(root.provider);
            if (url)
                Qt.openUrlExternally(url);
        }
    }

    DButton {
        visible: !((root.provider?.resets?.available ?? 0) > 0) && u.providerLink(root.provider) !== ""
        variant: "text"
        text: "Open usage page"
        iconName: "open_in_new"
        onClicked: {
            var url = u.providerLink(root.provider);
            if (url)
                Qt.openUrlExternally(url);
        }
    }
}
