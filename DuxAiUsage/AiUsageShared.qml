import QtQuick
import qs.Common

// One shared copy of every AI-usage formatting rule. Every surface
// (pill, popout, dash tab, overview card, desktop widget) instantiates
// this and calls the same functions, so color/headline/stale behavior
// cannot drift between surfaces. The threshold and headline rules
// themselves live in collectors/model.py (unit-tested); this file only
// formats the snapshot collect.py annotates (headlineId,
// headlineShort, staleSince).
QtObject {
    id: root

    // Strong red for critical/blocked. Why not Theme.error: in the
    // default dark themes Theme.error is a pale salmon, which reads as
    // "info" next to amber. Critical must be unmistakable.
    readonly property color critColor: "#F44336"

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

    function logoFor(providerId) {
        var names = {"claude": "claude", "codex": "codex", "opencodeGo": "opencode"};
        var name = names[providerId] ?? "opencode";
        return Qt.resolvedUrl("assets/" + name + ".svg");
    }

    function providerLink(provider) {
        return provider?.usageUrl ?? provider?.resets?.url ?? "";
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

    // The last-known tag shows only for values kept from a failed/429
    // poll (provider.stale), with the age of those values.
    function staleText(provider, fetchedAt, nowMs) {
        if (provider?.stale !== true)
            return "";
        var since = provider?.staleSince ?? fetchedAt;
        var ago = root.ageText(since, nowMs);
        if (ago === "" || ago === "just now")
            return "· last-known";
        return "· last-known " + ago;
    }
}
