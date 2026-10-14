// Pure helpers for the capture indicator; `node Model.test.js` checks them.

var MAX_SESSIONS = 20
// A capture that restarts this soon after ending is the same capture (Hyprland
// flips screencast to 0 whenever frames pause for half a second).
var MERGE_MS = 3000

// probe.sh lines are "A name" (actively capturing) or "N name" (a capture tool
// that is running). N names only count when nothing is actively capturing, so
// an idle OBS isn't blamed for a browser share.
function parseProbe(text) {
  var lines = String(text || "").split("\n")
  var seen = { A: [], N: [] }
  for (var i = 0; i < lines.length; i++) {
    var m = /^([AN]) (.+)$/.exec(lines[i].trim())
    if (m && seen[m[1]].indexOf(m[2]) === -1) seen[m[1]].push(m[2])
  }
  var active = seen.A.length > 0
  return { active: active, names: active ? seen.A : seen.N }
}

// screencastv2 data: "STATE,OWNER,NAME" with OWNER monitor or window.
function targetFromEvent(data) {
  var parts = String(data || "").split(",")
  var kind = parts[1] === "window" ? "Window" : parts[1] === "region" ? "Region" : "Screen"
  var name = parts.slice(2).join(",")
  return name ? kind + " " + name : kind
}

// Each target can stop independently; repeated events leave the state alone.
function updateTargets(targets, data) {
  var match = /^([01]),(monitor|window|region),(.*)$/.exec(String(data || ""))
  if (!match) return targets
  var key = match[2] + "," + match[3]
  var index = targets.indexOf(key)
  if (match[1] === "1") return index < 0 ? targets.concat([key]) : targets
  if (index < 0) return targets
  return targets.filter(function(target) { return target !== key })
}

function begin(history, now, target) {
  var last = history[history.length - 1]
  if (last && !last.end) return history
  var list = history.slice()
  if (last && last.end && now - last.end < MERGE_MS) {
    list[list.length - 1] = Object.assign({}, last, { end: 0 })
    return list
  }
  list.push({ start: now, end: 0, apps: [], target: target || "Screen" })
  return list.slice(-MAX_SESSIONS)
}

function finish(history, now) {
  var last = history[history.length - 1]
  if (!last || last.end) return history
  var list = history.slice()
  list[list.length - 1] = Object.assign({}, last, { end: now })
  return list
}

// Names arrive from a probe that may land just after a quick screenshot ended.
function addApps(history, names, now) {
  var last = history[history.length - 1]
  if (!last || !names.length || (last.end && now - last.end > MERGE_MS)) return history
  var apps = last.apps
  for (var i = 0; i < names.length; i++) {
    if (apps.indexOf(names[i]) !== -1) continue
    if (apps === last.apps) apps = apps.slice()
    apps.push(names[i])
  }
  if (apps === last.apps) return history
  var list = history.slice()
  list[list.length - 1] = Object.assign({}, last, { apps: apps })
  return list
}

function duration(session, now) {
  var s = Math.round(((session.end || now) - session.start) / 1000)
  if (s < 1) return "snapshot"
  if (s < 60) return s + " s"
  return Math.floor(s / 60) + " min " + (s % 60) + " s"
}

function appsLabel(session) {
  return session.apps.length ? session.apps.join(", ") : "Unknown app"
}

if (typeof module !== "undefined") {
  module.exports = { parseProbe: parseProbe, targetFromEvent: targetFromEvent, updateTargets: updateTargets, begin: begin,
    finish: finish, addApps: addApps, duration: duration, appsLabel: appsLabel }
}
