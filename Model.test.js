var M = require("./Model.js"), assert = require("assert")

var p = M.parseProbe("N grim\nA Brave\nA Brave\n<junk>\n")
assert.deepStrictEqual(p, { active: true, names: ["Brave"] })
assert.deepStrictEqual(M.parseProbe("N grim\nN omarchy-capture-screenshot"), { active: false, names: ["grim", "omarchy-capture-screenshot"] })
assert.strictEqual(M.parseProbe("N obs\n").active, false)
assert.strictEqual(M.targetFromEvent("1,monitor,eDP-1"), "Screen eDP-1")
assert.strictEqual(M.targetFromEvent("1,window,foo, bar"), "Window foo, bar")
assert.strictEqual(M.targetFromEvent("1,region,"), "Region")

// Ending one target must not hide another capture; duplicate events do no work.
var targets = M.updateTargets([], "1,monitor,display")
assert.strictEqual(M.updateTargets(targets, "1,monitor,display"), targets)
assert.strictEqual(M.updateTargets(targets, "0,window,other"), targets)
assert.strictEqual(M.updateTargets(targets, "bad event"), targets)
targets = M.updateTargets(targets, "1,window,example")
targets = M.updateTargets(targets, "0,monitor,display")
assert.deepStrictEqual(targets, ["window,example"])
assert.deepStrictEqual(M.updateTargets(targets, "0,window,example"), [])

// quick screenshot: names arrive after it ended, still attach
var h = M.finish(M.begin([], 1000, "Screen eDP-1"), 1100)
h = M.addApps(h, ["grim"], 1300)
assert.deepStrictEqual(h[0].apps, ["grim"])
assert.strictEqual(M.duration(h[0]), "snapshot")
// stale names don't attach
assert.strictEqual(M.addApps(h, ["obs"], 99999), h)
// pause-flap merges into one session; a later capture is a new one
h = M.begin(h, 2000); assert.strictEqual(h.length, 1); assert.strictEqual(h[0].end, 0)
h = M.finish(h, 64000); assert.strictEqual(M.duration(h[0]), "1 min 3 s")
h = M.begin(h, 90000); assert.strictEqual(h.length, 2)
// capped
for (var i = 0; i < 30; i++) h = M.begin(M.finish(h, 1e6 + i * 1e4), 1e6 + i * 1e4 + 5000)
assert.strictEqual(h.length, 20)
// unchanged inputs return the same array (no needless re-render)
var done = M.finish(h, 2e6); assert.strictEqual(M.finish(done, 3e6), done)
assert.strictEqual(M.begin(h, 2e6), h)
h = M.addApps(h, ["Example app"], 2e6)
assert.strictEqual(M.addApps(h, ["Example app", "Example app"], 2e6), h)
var originalApps = h[h.length - 1].apps
var updated = M.addApps(h, ["Other app", "Other app"], 2e6)
assert.deepStrictEqual(originalApps, ["Example app"])
assert.deepStrictEqual(updated[updated.length - 1].apps, ["Example app", "Other app"])
assert.strictEqual(M.duration({ start: 1000, end: 0 }, 3000), "2 s")
assert.strictEqual(M.appsLabel({ apps: [] }), "Unknown app")
assert.strictEqual(M.appsLabel({ apps: ['<img src="https://example.invalid/">'] }), '<img src="https://example.invalid/">')
console.log("Model tests PASS")
