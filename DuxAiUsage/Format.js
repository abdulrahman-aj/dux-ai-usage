.pragma library

// Trivial display formatting for duxAiUsage surfaces. Threshold and
// merge rules live in collectors/model.py (unit-tested); this file only
// turns numbers into short strings.

function shortCode(providerId, windowId) {
    var providers = {"claude": "Cl", "codex": "Cx", "opencodeGo": "Go"};
    var windows = {"fiveHour": "5h", "rolling": "5h", "weekly": "W",
                   "monthly": "M", "weekly-fable": "F"};
    return {"provider": providers[providerId] ?? providerId,
            "window": windows[windowId] ?? windowId};
}

function pctText(percent) {
    if (percent === null || percent === undefined || isNaN(percent))
        return "–";
    return Math.round(percent) + "%";
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
    return days + "d " + (hours - days * 24) + "h";
}
