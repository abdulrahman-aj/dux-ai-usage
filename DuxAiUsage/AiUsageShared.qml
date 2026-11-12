import QtQuick
import qs.Common

// One shared copy of every AI-usage formatting rule. Every surface
// (pill, popout, dash tab, overview card, desktop widget) instantiates
// this and calls the same functions, so color/headline/stale behavior
// cannot drift between surfaces. The threshold and headline rules
// themselves live in collectors/model.py (unit-tested); this file only
// formats the snapshot collect.py annotates (headlineId,
// headlineShort, updatedAt).
QtObject {
    id: root

    // Strong red for critical/blocked. Why not Theme.error: in the
    // default dark themes Theme.error is a pale salmon, which reads as
    // "info" next to amber. Critical must be unmistakable.
    readonly property color critColor: "#F44336"

    // Surface metrics for the cards, popout, Dash tab and desktop
    // widget. Same recipe as Dux's own metrics singletons (PopoutMetrics,
    // CcMetrics): a base token plus a density step, floored so "dense"
    // stays legible. spacious / comfortable / compact / dense:
    //   cardPad 16 / 12 / 8 / 6, rowGap 10 / 8 / 6 / 4.
    // The bar pill never uses these: Dux keeps the bar fixed.
    readonly property real cardPad: Math.max(Theme.spacingXS + Theme.spacingXXS, Theme.spacingM + Theme.densityStepS)
    readonly property real rowGap: Math.max(Theme.spacingXS, Theme.spacingS + Theme.densityStepXS)
    // Meter track: the 4px line Dux's SystemMonitor widget uses, tinted
    // like Dux's Dash meters (content color at the focus state alpha).
    readonly property real meterHeight: Theme.spacingXS
    readonly property color meterTrack: Theme.withAlpha(Theme.surfaceText, Theme.stateLayerFocus)

    // Clamp the two threshold sliders the same way model.py does, so a
    // pill can never color crit while the daemon toasts warn (or take
    // over a different headline): every surface derives its levels
    // from these, never from the raw settings.
    function clampedThresholds(warn, crit) {
        if (!(warn >= 0))
            warn = 80;
        if (!(crit > warn))
            crit = warn + 1;
        return [warn, crit];
    }

    // One filter for every surface: the enabled providers in snapshot
    // order. Takes the whole settings object so the ?? defaults live
    // here too, not copied per surface.
    function visibleProviders(snapshot, settings) {
        var all = snapshot?.providers ?? [];
        var showClaude = settings?.enableClaude ?? true;
        var showCodex = settings?.enableCodex ?? true;
        var showGo = settings?.enableGo ?? true;
        return all.filter(p => (p.id === "claude" && showClaude) || (p.id === "codex" && showCodex) || (p.id === "opencodeGo" && showGo));
    }

    function levelOf(percent, warn, crit) {
        if (percent === null || percent === undefined || isNaN(percent))
            return "unknown";
        if (percent >= crit)
            return "crit";
        if (percent >= warn)
            return "warn";
        return "ok";
    }

    // The single color rule used by every surface: theme accent when
    // calm, amber at warning, strong red at critical/blocked.
    function stateColor(level) {
        if (level === "crit")
            return root.critColor;
        if (level === "warn")
            return Theme.warning;
        if (level === "ok")
            return Theme.primary;
        return Theme.surfaceVariantText;
    }

    // Headline window for a provider: collect.py annotates headlineId
    // (see model.headline_window). No fallback: every snapshot the
    // daemon serves carries the annotation.
    function headlineWindow(provider) {
        var windows = provider?.windows ?? [];
        var want = provider?.headlineId;
        for (var i = 0; i < windows.length; i++) {
            if (windows[i]?.id === want)
                return windows[i];
        }
        return null;
    }

    function headlineLevel(provider, warn, crit) {
        var window = root.headlineWindow(provider);
        if (provider?.error)
            return "unknown";
        if (!window)
            return "unknown";
        return root.levelOf(window.usedPercent, warn, crit);
    }

    // Tiny mark identifying a short headline window ("5h", "W", "M").
    // Shown only on takeover; the normal state is logo + number alone.
    function shortMark(windowId) {
        var known = {"fiveHour": "5h", "rolling": "5h", "weekly": "W", "monthly": "M"};
        if (known[windowId])
            return known[windowId];
        return "";
    }

    function logoName(providerId) {
        if (providerId === "claude")
            return "claude";
        if (providerId === "codex")
            return "codex";
        return "opencode";
    }

    function logoFor(providerId) {
        return Qt.resolvedUrl("assets/" + logoName(providerId) + ".svg");
    }

    function providerLink(provider) {
        return provider?.usageUrl ?? "";
    }

    function pctText(percent) {
        if (percent === null || percent === undefined || isNaN(percent))
            return "–";
        return Math.round(percent) + "%";
    }

    function countdown(resetsAt, nowMs) {
        if (!resetsAt)
            return "";
        var ms = new Date(resetsAt).getTime() - (nowMs ?? Date.now());
        if (!(ms > 0))
            return "soon";
        var mins = Math.ceil(ms / 60000);
        if (mins < 60)
            return mins + "m";
        var hours = Math.floor(mins / 60);
        var rest = mins - hours * 60;
        if (hours < 48)
            return rest === 0 ? hours + "h" : hours + "h " + rest + "m";
        var days = Math.floor(hours / 24);
        var dayRest = hours - days * 24;
        return dayRest === 0 ? days + "d" : days + "d " + dayRest + "h";
    }

    function ageText(isoString, nowMs) {
        if (!isoString)
            return "";
        var ms = (nowMs ?? Date.now()) - new Date(isoString).getTime();
        if (!(ms > 0))
            return "just now";
        var mins = Math.floor(ms / 60000);
        if (mins < 1)
            return "just now";
        if (mins < 60)
            return mins + "m";
        var hours = Math.floor(mins / 60);
        if (hours < 48)
            return hours + "h";
        return Math.floor(hours / 24) + "d";
    }

    function updatedText(stamp, nowMs) {
        if (!stamp)
            return "Waiting for first poll…";
        var ago = root.ageText(stamp, nowMs);
        if (ago === "just now" || ago === "")
            return "Updated just now";
        return "Updated " + ago + " ago";
    }

    // Each provider's own last successful fetch: the collector stamps
    // updatedAt on fresh polls and preserves it across 429 reuse (see
    // model.merge_rate_limited), falling back to the kept staleSince.
    // Cards show this when their values are last-known, so a
    // rate-limited Claude reads "Limiting usage checks · updated 8m
    // ago" instead of a bare age that looks merely stale, while a fresh
    // Codex shows nothing. Without any kept stamp (e.g. a first poll
    // that hits 429 with nothing cached) nothing shows: the error hint
    // already explains the state.
    function providerUpdatedAt(provider) {
        return provider?.updatedAt ?? provider?.staleSince ?? "";
    }

    function providerUpdatedText(provider, nowMs) {
        if (provider?.stale !== true && provider?.rateLimited !== true)
            return "";
        var stamp = root.providerUpdatedAt(provider);
        if (!stamp)
            return "";
        var ago = root.updatedText(stamp, nowMs);
        if (provider?.rateLimited === true)
            return "Limiting usage checks · " + ago.charAt(0).toLowerCase() + ago.slice(1);
        return ago;
    }

    // Resets line: "N reset(s) available" with type and expiry when
    // present (Claude grants + weekly reset, Codex rateLimitResetCredits).
    // Returns "" when nothing is banked so callers stay quiet/omitted.
    function resetsLine(provider, nowMs) {
        var r = provider?.resets;
        if (!r || !(r.available > 0))
            return "";
        var n = r.available;
        var out = n + (n === 1 ? " reset available" : " resets available");
        if (r.label)
            out += " · " + r.label;
        if (r.resetsAt) {
            var cd = countdown(r.resetsAt, nowMs);
            if (cd && cd !== "soon")
                out += " · expires in " + cd;
            else if (cd === "soon")
                out += " · expiring soon";
        }
        return out;
    }
}
