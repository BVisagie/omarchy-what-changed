// Intake and formatting for the What Changed overlay.
//
// Everything the CLI hands over is untrusted: package names come out of
// pacman.log and release bodies out of GitHub. Intake rebuilds each object from
// known fields only, so anything unexpected in the payload is dropped rather
// than carried into the view, and every string is control-character flattened
// and length-capped before it can reach a Text element.

var MAX_NAME = 128
var MAX_VERSION = 64
var MAX_TITLE = 120
var MAX_SHORT = 32
var MAX_MESSAGE = 400
var MAX_BODY = 200000
var MAX_ITEMS = 500
var MAX_GROUPS = 16
var MAX_SESSIONS = 50
var MAX_RELEASES = 24

// Controls, C1, bidi overrides, zero-width marks and the BOM are matched by
// code point rather than by a literal character class, so nothing invisible
// has to survive a round trip through this file for the filter to stay right.
function isHidden(code, keepBreaks) {
  if (keepBreaks && (code === 9 || code === 10)) return false
  if (code < 32 || code === 127) return true
  if (code >= 128 && code <= 159) return true
  if (code >= 8203 && code <= 8207) return true
  if (code === 8232 || code === 8233) return true
  if (code >= 8234 && code <= 8238) return true
  if (code >= 8294 && code <= 8297) return true
  return code === 65279
}

function scrub(value, keepBreaks) {
  var s = String(value)
  var out = []
  for (var i = 0; i < s.length; i++)
    out.push(isHidden(s.charCodeAt(i), keepBreaks) ? " " : s.charAt(i))
  return out.join("")
}

// Single-line text: newlines collapse, because these land in one-line rows.
function text(value, limit) {
  if (value === null || value === undefined) return ""
  var s = scrub(value, false).replace(/\s+/g, " ").replace(/^ +| +$/g, "")
  if (s.length > limit) s = s.slice(0, limit) + "…"
  return s
}

// Release bodies keep their line structure; every other control still goes.
function multiline(value, limit) {
  if (value === null || value === undefined) return ""
  var s = scrub(String(value).replace(/\r\n?/g, "\n"), true)
  s = s.replace(/[ \t]+$/gm, "").replace(/\n{4,}/g, "\n\n\n")
  if (s.length > limit) s = s.slice(0, limit) + "\n…"
  return s
}

function count(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return 0
  return Math.floor(n)
}

function intakeCounts(raw) {
  var src = (raw && typeof raw === "object") ? raw : {}
  return {
    upgraded: count(src.upgraded), installed: count(src.installed),
    removed: count(src.removed), downgraded: count(src.downgraded),
    reinstalled: count(src.reinstalled), aur: count(src.aur),
    total: count(src.total), omitted: count(src.omitted)
  }
}

function intakeSession(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = text(raw.id, MAX_SHORT)
  if (!id) return null
  var om = (raw.omarchy && typeof raw.omarchy === "object") ? raw.omarchy : {}
  var reason = []
  if (Array.isArray(raw.rebootReason))
    for (var i = 0; i < raw.rebootReason.length && reason.length < 8; i++)
      reason.push(text(raw.rebootReason[i], MAX_NAME))
  return {
    id: id,
    label: text(raw.label, MAX_SHORT),
    channel: text(raw.channel, MAX_SHORT),
    source: text(raw.source, MAX_SHORT),
    incomplete: raw.incomplete === true,
    rebootRequired: raw.rebootRequired === true,
    rebootReason: reason,
    omarchy: {
      name: text(om["package"], MAX_NAME),
      from: text(om.from, MAX_VERSION),
      to: text(om.to, MAX_VERSION),
      jumped: om.jumped === true
    },
    counts: intakeCounts(raw.counts)
  }
}

function intakeItem(raw) {
  if (!raw || typeof raw !== "object") return null
  var name = text(raw.name, MAX_NAME)
  if (!name) return null
  var isMigration = raw.kind === "migration"
  return {
    kind: isMigration ? "migration" : "pkg",
    op: isMigration ? "" : text(raw.op, MAX_SHORT),
    name: name,
    from: isMigration ? "" : text(raw.from, MAX_VERSION),
    to: isMigration ? "" : text(raw.to, MAX_VERSION),
    aur: raw.aur === true
  }
}

function intakeGroup(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = text(raw.id, MAX_SHORT)
  if (!id) return null
  var items = []
  if (Array.isArray(raw.items))
    for (var i = 0; i < raw.items.length && items.length < MAX_ITEMS; i++) {
      var item = intakeItem(raw.items[i])
      if (item) items.push(item)
    }
  // A collapsed group reports how much it stands for while carrying nothing,
  // so the count is the CLI's and not a length we can infer from items.
  var declared = raw.count === undefined ? items.length : count(raw.count)
  return {
    id: id,
    title: text(raw.title, MAX_TITLE),
    collapsed: raw.collapsed === true,
    count: declared,
    items: items
  }
}

function parse(jsonText) {
  try {
    var value = JSON.parse(String(jsonText === undefined ? "" : jsonText))
    return (value && typeof value === "object") ? value : null
  } catch (e) {
    return null
  }
}

function parseSessions(jsonText) {
  var raw = parse(jsonText)
  if (!raw || !Array.isArray(raw.sessions))
    return { ok: false, sessions: [], error: "Could not read the session list." }
  var out = []
  for (var i = 0; i < raw.sessions.length && out.length < MAX_SESSIONS; i++) {
    var s = intakeSession(raw.sessions[i])
    if (s) out.push(s)
  }
  if (out.length === 0)
    return { ok: false, sessions: [], error: "No update sessions found." }
  return { ok: true, sessions: out, error: "" }
}

function parseShow(jsonText) {
  var raw = parse(jsonText)
  var session = raw ? intakeSession(raw.session) : null
  if (!session)
    return { ok: false, session: null, groups: [], error: "Could not read this session." }
  var groups = []
  if (Array.isArray(raw.groups))
    for (var i = 0; i < raw.groups.length && groups.length < MAX_GROUPS; i++) {
      var g = intakeGroup(raw.groups[i])
      if (g) groups.push(g)
    }
  return {
    ok: true, session: session, groups: groups, error: "",
    outputTruncated: raw.outputTruncated === true
  }
}

// The bar widget's whole read model: is there a session the user has not seen?
function parseStatus(jsonText) {
  var raw = parse(jsonText)
  if (!raw) return { ok: false, unread: false, newest: null, lastRead: "" }
  return {
    ok: true,
    unread: raw.unread === true,
    newest: intakeSession(raw.newest),
    lastRead: text(raw.lastRead, MAX_SHORT)
  }
}

function parseNotes(jsonText) {
  var raw = parse(jsonText)
  if (!raw)
    return { ok: false, status: "error", releases: [],
             message: "Could not read the release notes." }
  var status = text(raw.status, MAX_SHORT)
  var releases = []
  if (Array.isArray(raw.releases))
    for (var i = 0; i < raw.releases.length && releases.length < MAX_RELEASES; i++) {
      var r = raw.releases[i]
      if (!r || typeof r !== "object") continue
      releases.push({
        tag: text(r.tag, MAX_SHORT),
        name: text(r.name, MAX_TITLE),
        url: safeUrl(r.url),
        body: multiline(r.body, MAX_BODY)
      })
    }
  return {
    ok: (status === "ok" || status === "partial") && releases.length > 0,
    status: status,
    releases: releases,
    message: text(raw.message, MAX_MESSAGE)
  }
}

// Only an https link into a GitHub repo is ever handed to a browser.
function safeUrl(value) {
  var s = text(value, 200)
  return /^https:\/\/github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/[A-Za-z0-9._\/-]*$/.test(s) ? s : ""
}

// ---------------------------------------------------------------- formatting

function versionText(item) {
  if (!item || item.kind === "migration") return ""
  if (item.op === "removed") return "removed " + item.from
  if (item.from && item.to) return item.from + " → " + item.to
  if (item.op === "installed") return "installed " + item.to
  if (item.op === "reinstalled") return "reinstalled " + item.to
  return item.to
}

function jumpText(session) {
  if (!session) return ""
  var om = session.omarchy
  if (om.jumped && om.from && om.to) return "omarchy " + om.from + " → " + om.to
  if (om.to) return "omarchy " + om.to
  return "omarchy version unknown"
}

function countsText(counts) {
  if (!counts) return ""
  var parts = []
  if (counts.upgraded)    parts.push(counts.upgraded + " upgraded")
  if (counts.installed)   parts.push(counts.installed + " installed")
  if (counts.removed)     parts.push(counts.removed + " removed")
  if (counts.downgraded)  parts.push(counts.downgraded + " downgraded")
  if (counts.reinstalled) parts.push(counts.reinstalled + " reinstalled")
  if (parts.length === 0) return "No package changes"
  var noun = counts.total === 1 ? " package change: " : " package changes: "
  return counts.total + noun + parts.join(", ")
}

function headerText(session) {
  if (!session) return ""
  var parts = [session.label, jumpText(session)]
  if (session.channel && session.channel !== "unknown") parts.push(session.channel)
  if (session.rebootRequired) parts.push("reboot needed")
  return parts.join("  ·  ")
}

function sessionSummary(session) {
  if (!session) return ""
  var c = session.counts
  var parts = []
  if (c.upgraded)    parts.push(c.upgraded + "↑")
  if (c.installed)   parts.push(c.installed + "+")
  if (c.removed)     parts.push(c.removed + "-")
  if (c.downgraded)  parts.push(c.downgraded + "↓")
  if (c.reinstalled) parts.push(c.reinstalled + "↻")
  return parts.join(" ")
}

function sessionVersion(session) {
  if (!session) return ""
  var strip = function (v) { return String(v || "").replace(/-[0-9]+$/, "") }
  var om = session.omarchy
  if (om.jumped && om.from && om.to) return strip(om.from) + " → " + strip(om.to)
  return strip(om.to)
}

if (typeof module !== "undefined" && module.exports)
  module.exports = {
    text: text, multiline: multiline, safeUrl: safeUrl,
    intakeSession: intakeSession, intakeItem: intakeItem, intakeGroup: intakeGroup,
    parseSessions: parseSessions, parseShow: parseShow, parseNotes: parseNotes,
    parseStatus: parseStatus,
    versionText: versionText, jumpText: jumpText, countsText: countsText,
    headerText: headerText, sessionSummary: sessionSummary,
    sessionVersion: sessionVersion
  }
