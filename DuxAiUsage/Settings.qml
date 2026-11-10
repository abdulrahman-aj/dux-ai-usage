import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "duxAiUsage"

    StyledText {
        width: parent.width
        text: "Polling"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    SliderSetting {
        settingKey: "pollMinutes"
        label: "Poll interval"
        description: "How often usage is refreshed (shared by all surfaces)"
        defaultValue: 5
        minimum: 2
        maximum: 30
        unit: "min"
    }

    StyledText {
        width: parent.width
        text: "Providers"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "enableClaude"
        label: "Claude"
        description: "Claude Code subscription (5-hour + weekly)"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "enableCodex"
        label: "Codex"
        description: "ChatGPT plan via Codex CLI (5-hour + weekly)"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "enableGo"
        label: "OpenCode Go"
        description: "Single workspace from the stored Go key"
        defaultValue: true
    }

    StyledText {
        width: parent.width
        text: "Thresholds"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    SliderSetting {
        settingKey: "warnThreshold"
        label: "Warning at"
        description: "Pill turns amber and a warning toast fires once per window"
        defaultValue: 80
        minimum: 50
        maximum: 99
        unit: "%"
    }

    SliderSetting {
        settingKey: "critThreshold"
        label: "Critical at"
        description: "Pill turns red and a critical toast fires once per window"
        defaultValue: 100
        minimum: 51
        maximum: 100
        unit: "%"
    }

    StyledText {
        width: parent.width
        text: "Toasts"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "toastsEnabled"
        label: "Threshold toasts"
        description: "Notify once per window per crossing (warning, critical)"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "resetNotify"
        label: "Notify on reset"
        description: "Notify when an exhausted window starts a fresh period"
        defaultValue: true
    }
}
