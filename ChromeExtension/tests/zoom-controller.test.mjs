import test from "node:test";
import assert from "node:assert/strict";
import { ZoomController, parseState } from "../zoom-controller.mjs";

const external = (generation = 1, factor = 1.25) => ({
  enabled: true, chromeEnabled: true, externalConnected: true, chromeZoom: factor, generation,
});
const internal = generation => ({ ...external(generation), externalConnected: false });
function fixture(ids = [1, 2]) {
  const calls = [];
  const tabs = {
    query: async () => ids.map(id => ({ id })),
    setZoomSettings: async (id, settings) => calls.push({ kind: "scope", id, settings }),
    setZoom: async (id, factor) => calls.push({ kind: "zoom", id, factor }),
  };
  return { calls, tabs, controller: new ZoomController(tabs) };
}

test("external profile applies exact factors without modifying saved site zoom", async () => {
  const { calls, controller } = fixture();
  assert.equal(await controller.acceptState(external(1, 1.2)), true);
  assert.equal(calls.filter(c => c.kind === "zoom").length, 2);
  assert.ok(calls.filter(c => c.kind === "zoom").every(c => c.factor === 1.2));
  assert.ok(calls.filter(c => c.kind === "scope").every(c => c.settings.scope === "per-tab"));
});

test("unplug restores exactly 100%, independent of previous external target", async () => {
  const { calls, controller } = fixture();
  await controller.acceptState(external());
  calls.length = 0;
  await controller.acceptState(internal(2));
  assert.deepEqual(calls.filter(c => c.kind === "zoom").map(c => c.factor), [1, 1]);
});

test("duplicate state and activation do not fight a user's temporary manual zoom", async () => {
  const { calls, controller } = fixture();
  await controller.acceptState(external());
  calls.length = 0;
  await controller.acceptState(external());
  await controller.applyTab(1);
  assert.equal(calls.length, 0);
  await controller.applyTab(1, true); // new navigation resets per-tab scope
  assert.equal(calls.filter(c => c.kind === "zoom").length, 1);
});

test("invalid or disconnected configuration never adjusts tabs", async () => {
  const { calls, controller } = fixture();
  assert.equal(await controller.acceptState({ ...external(), chromeZoom: NaN }), false);
  assert.equal(parseState({ ...external(), chromeZoom: 99 }), null);
  assert.equal(parseState({ ...external(), enabled: "true" }), null);
  await controller.applyTab(1, true);
  assert.equal(calls.length, 0);
  await controller.acceptState(external());
  calls.length = 0;
  controller.disconnect();
  await controller.applyTab(1, true);
  assert.equal(calls.length, 0);
});

test("restricted tab does not prevent other tabs being updated", async () => {
  const { tabs, calls, controller } = fixture();
  const original = tabs.setZoomSettings;
  tabs.setZoomSettings = async (id, settings) => {
    if (id === 1) throw new Error("Cannot access a chrome:// URL");
    return original(id, settings);
  };
  await controller.acceptState(external());
  assert.deepEqual(calls.filter(c => c.kind === "zoom").map(c => c.id), [2]);
});

test("profile changes while an API call awaits use the latest factor", async () => {
  const { tabs, calls, controller } = fixture([1]);
  let release;
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  tabs.setZoomSettings = async () => { entered(); await gate; };
  const connecting = controller.acceptState(external());
  await started;
  const unplugging = controller.acceptState(internal(2));
  release();
  await Promise.all([connecting, unplugging]);
  assert.ok(calls.filter(c => c.kind === "zoom").every(c => c.factor === 1));
});

test("disabling while an API call awaits prevents further zoom writes", async () => {
  const { tabs, calls, controller } = fixture([1]);
  let release;
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  tabs.setZoomSettings = async () => { entered(); await gate; };
  const connecting = controller.acceptState(external());
  await started;
  await controller.acceptState({ ...external(2), enabled: false });
  release();
  await connecting;
  assert.equal(calls.filter(c => c.kind === "zoom").length, 0);
});
