// Runs Model.js outside the shell. Usage: node tests/model.test.js
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const assert = require("node:assert/strict")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Model = {}
vm.runInContext(source + "\n" + exportsList(source), vm.createContext({ Model }))

function exportsList(src) {
  const names = new Set()
  for (const m of src.matchAll(/^(?:var|function)\s+([A-Za-z_]\w*)/gm)) names.add(m[1])
  return [...names].map((n) => `Model.${n} = ${n}`).join("\n")
}

const tests = []
const test = (name, fn) => tests.push([name, fn])
const same = (actual, expected) => assert.equal(JSON.stringify(actual), JSON.stringify(expected))

// Persistence blob names: account id is a fixture, not a real auth id.
const ROSTER_FILE = "onqw4zbomnwgszlooqxhg3djmnss4yldmnxxk3tufztxe33leu3ug5ltmvzf6mbrivmectkqjrcvirktkqydambqgaydambqgaydaltsn5zxizlsfzwgc43ufvzg643umvza.blob"
const TRANSCRIPT_FILE = "onqw4zbomnwgszlooqxhg3djmnss4yldmnxxk3tufztxe33leu3ug5ltmvzf6mbrivmectkqjrcvirktkqydambqgaydambqgaydaltuojqw443dojuxa5boojsxa3djmnqxglrxg43tknjwgbtc2yldgi4c2nbtgyys2yjqgy2c2njvmq3giodgmrstqytb.blob"
const LAYOUT_FILE = "onqw4zbomnwgszlooqxhg3djmnss45ljfvwgc6lpov2a.blob"

const NOW = 1788489540000

const roster = {
  schemaVersion: 2,
  value: {
    rows: [
      { id: "a-1", name: "Architect", hasUnread: true, unreadCount: 1, lastActivityAt: NOW - 30000, lastViewedAt: NOW - 60000,
        awaitingUserResponse: null, notifyOnUpdatesEnabled: true, isHiddenFromSidebar: false, isGroup: false,
        lastEntry: { kind: "text", text: "Scanning both repos for quick wins — open issues, CI, and le" } },
      { id: "b-2", name: "Inbox Triage", hasUnread: false, unreadCount: 0, lastActivityAt: NOW - 90000,
        awaitingUserResponse: { reason: "approval_required", reasonCopy: "" },
        lastEntry: { kind: "text", text: "Cron failure cleanup:\n\n**Gmail** — none of those leftover jobs" } },
      { id: "c-3", name: "Chief of Staff", hasUnread: false, unreadCount: 0, lastActivityAt: NOW - 5000,
        awaitingUserResponse: null, lastEntry: { kind: "text", text: "Message from Inbox Triage: On it. Cleaning" } },
      { id: "d-4", name: "Secret", isHiddenFromSidebar: true, lastActivityAt: NOW },
      { id: "e-5", name: "QA", hasUnread: false, unreadCount: 0, lastActivityAt: NOW - 3600000,
        lastEntry: { kind: "text", text: "Message from Chief of Staff: the user just created you" } }
    ]
  }
}

test("base32 decodes the persistence key and unescapes the pipe", () => {
  const key = Model.blobKey(ROSTER_FILE)
  assert.equal(key, "sand.client.slice.account.grok|user_01EXAMPLETEST000000000000.roster.last-roster")
})

test("classifies roster, transcript and unrelated blobs", () => {
  assert.equal(Model.classifyBlob(ROSTER_FILE).kind, "roster")
  const t = Model.classifyBlob(TRANSCRIPT_FILE)
  assert.equal(t.kind, "transcript")
  assert.equal(t.agentId, "7775560f-ac28-4361-a064-55d6d8fde8ba")
  assert.equal(Model.classifyBlob(LAYOUT_FILE).kind, "other")
  assert.equal(Model.classifyBlob("README.txt").kind, "other")
  assert.equal(Model.classifyBlob("not base32!.blob").kind, "other")
})

test("finds the roster in a listing and indexes transcripts", () => {
  assert.equal(Model.findRosterFile([LAYOUT_FILE, TRANSCRIPT_FILE, ROSTER_FILE]), ROSTER_FILE)
  assert.equal(Model.findRosterFile([LAYOUT_FILE]), "")
  same(Model.transcriptIndex([LAYOUT_FILE, TRANSCRIPT_FILE]), { [TRANSCRIPT_FILE]: "7775560f-ac28-4361-a064-55d6d8fde8ba" })
})

test("parses the roster and cleans previews", () => {
  const parsed = Model.parseRoster(JSON.stringify(roster))
  assert.equal(parsed.ok, true)
  assert.equal(parsed.rows.length, 5)
  const inbox = parsed.rows[1]
  assert.equal(inbox.awaiting.reason, "approval_required")
  assert.equal(inbox.lastText, "Cron failure cleanup:")
  assert.equal(parsed.rows[2].lastText, "On it. Cleaning")
  assert.equal(parsed.rows[0].lastText, "Scanning both repos for quick wins — open issues, CI, and le")
})

test("rejects bad rosters without throwing", () => {
  assert.equal(Model.parseRoster("{nope").ok, false)
  assert.equal(Model.parseRoster("null").ok, false)
  assert.equal(Model.parseRoster(JSON.stringify({ schemaVersion: 2, value: {} })).ok, false)
  const emptyNewer = Model.parseRoster(JSON.stringify({ schemaVersion: 9, value: { rows: [] } }))
  assert.equal(emptyNewer.ok, true)
  assert.equal(emptyNewer.rows.length, 0)
  const unreadable = Model.parseRoster(JSON.stringify({ schemaVersion: 9, value: { rows: [{ notAnAgent: true }] } }))
  assert.equal(unreadable.ok, false)
  assert.equal(unreadable.schemaTooNew, true)
  const moved = Model.parseRoster(JSON.stringify({ schemaVersion: 9, value: { agents: [] } }))
  assert.equal(moved.ok, false)
  assert.equal(moved.schemaTooNew, true)
})

test("parses Grok Bot 0.29 schema 3 and a free-text waiting reason", () => {
  const v29 = {
    schemaVersion: 3,
    value: {
      rows: [
        {
          id: "qa-1",
          name: "QA",
          hasUnread: true,
          unreadCount: 2,
          lastActivityAt: NOW,
          lastViewedAt: NOW - 1000,
          awaitingUserResponse: {
            tabId: "box",
            reason: "Open github.com/login/device and approve the workflow scope",
            since: NOW - 5000
          },
          lastEntry: { kind: "text", text: "Waiting on your merge." },
          notifyOnUpdatesEnabled: true,
          isHiddenFromSidebar: false,
          isGroup: false
        },
        {
          id: "cos-1",
          name: "Chief of Staff",
          hasUnread: false,
          unreadCount: 0,
          lastActivityAt: NOW - 10000,
          awaitingUserResponse: null,
          lastEntry: { kind: "text", text: "Standing by." }
        }
      ]
    }
  }
  const parsed = Model.parseRoster(JSON.stringify(v29))
  assert.equal(parsed.ok, true)
  assert.equal(parsed.schemaTooNew, undefined)
  assert.equal(parsed.rows.length, 2)
  assert.equal(parsed.rows[0].awaiting.reason, "Open github.com/login/device and approve the workflow scope")
  assert.equal(Model.reasonText(parsed.rows[0]), "Open github.com/login/device and approve the workflow scope")
  const newer = Model.parseRoster(JSON.stringify({ schemaVersion: 9, value: { rows: v29.value.rows } }))
  assert.equal(newer.ok, true)
  assert.equal(newer.rows[0].name, "QA")
})

test("derives states, hides hidden agents and orders by urgency", () => {
  const parsed = Model.parseRoster(JSON.stringify(roster))
  const agents = Model.decorate(parsed.rows, NOW, { "c-3": NOW - 4000 }, 12000)
  same(agents.map((a) => a.name + ":" + a.state), [
    "Inbox Triage:waiting", "Chief of Staff:working", "Architect:unread", "QA:idle"
  ])
  const counts = Model.countStates(agents)
  same(counts, { waiting: 1, working: 1, unread: 1, idle: 1, total: 4, unreadMessages: 1 })
  assert.equal(Model.mood(true, counts), "waiting")
  assert.equal(Model.mood(false, counts), "asleep")
  assert.equal(Model.badgeText(counts), "1")
})

test("working expires once the transcript stops changing", () => {
  const agent = { awaiting: null, hasUnread: false, unread: 0 }
  assert.equal(Model.agentState(agent, NOW, NOW - 3000, 12000), "working")
  assert.equal(Model.agentState(agent, NOW, NOW - 13000, 12000), "idle")
  assert.equal(Model.agentState({ awaiting: { reason: "x" }, unread: 0 }, NOW, NOW, 12000), "waiting")
})

test("copy for the hero, the tooltip and the pill", () => {
  const parsed = Model.parseRoster(JSON.stringify(roster))
  const agents = Model.decorate(parsed.rows, NOW, {}, 12000)
  const counts = Model.countStates(agents)
  assert.equal(Model.heroMeta(true, true, agents, counts, 0), "Inbox Triage needs you")
  assert.equal(Model.tooltip(true, true, agents, counts), "Inbox Triage needs you · 1 agent has updates")
  assert.equal(Model.pillLabel(["Inbox Triage"]), "Inbox Triage")
  assert.equal(Model.pillLabel(["Inbox Triage", "QA", "Architect"]), "Inbox Triage +2")
  assert.equal(Model.heroMeta(true, false, [], counts, 0), "Not running")
  assert.equal(Model.heroMeta(false, false, [], counts, 0), "Not installed")
  const quiet = Model.countStates([])
  assert.equal(Model.heroMeta(true, true, [], quiet, 0), "No agents yet")
  assert.equal(Model.reasonText(agents[0]), "Needs your approval")
  assert.equal(Model.reasonText({ awaiting: { reason: "mystery", copy: "" } }), "Waiting for your input")
  assert.equal(Model.reasonText({ awaiting: { reason: "mystery", copy: "Pick a colour" } }), "Pick a colour")
  assert.equal(Model.reasonText({ awaiting: { reason: "Open github.com/login/device", copy: "" } }), "Open github.com/login/device")
})

test("relative time is compact", () => {
  assert.equal(Model.relTime(NOW - 10000, NOW), "now")
  assert.equal(Model.relTime(NOW - 5 * 60000, NOW), "5m")
  assert.equal(Model.relTime(NOW - 3 * 3600000, NOW), "3h")
  assert.equal(Model.relTime(NOW - 3 * 86400000, NOW), "3d")
  assert.equal(Model.relTime(0, NOW), "")
})

test("session marker heartbeat", () => {
  const marker = JSON.stringify({ version: 1, pid: 42, appVersion: "0.24.0", aliveAtMs: NOW - 30000, crashSeen: false })
  same(Model.parseMarker(marker, NOW, 120000), { ok: true, alive: true, crashed: false, pid: 42, version: "0.24.0" })
  assert.equal(Model.parseMarker(marker, NOW + 300000, 120000).alive, false)
  assert.equal(Model.parseMarker("junk", NOW, 120000).ok, false)
})

test("control characters never reach the UI", () => {
  const agent = Model.parseAgent({ id: "x", name: "BadName[31m" })
  assert.equal(agent.name, "Bad Name [31m")
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log("ok   " + name)
  } catch (e) {
    failed++
    console.log("FAIL " + name + "\n     " + String(e.message).split("\n").join("\n     "))
  }
}
console.log(failed === 0 ? `\n${tests.length} passed` : `\n${failed} of ${tests.length} failed`)
process.exit(failed === 0 ? 0 : 1)
