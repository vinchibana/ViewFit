import { ZoomController, parseState } from "./zoom-controller.mjs";

const HOST = "com.avenry.screenscale";
const RECONNECT_ALARM = "screenscale-reconnect";
let nativePort = null;
let status = { connected: false, state: null, error: "正在连接 ViewFit · 随屏…", lastApplied: null, skipped: 0 };

const controller = new ZoomController(chrome.tabs, result => {
  if (result.ok) status.lastApplied = new Date().toISOString();
  else status.skipped += 1;
});

function refreshBadge() {
  const active = status.connected && status.state?.enabled && status.state?.chromeEnabled;
  const text = !status.connected ? "!" : active ? "" : "Ⅱ";
  chrome.action.setBadgeText({ text }).catch(() => {});
  chrome.action.setBadgeBackgroundColor({ color: !status.connected ? "#9D4329" : "#686868" }).catch(() => {});
}

function connect() {
  if (nativePort) return;
  try {
    const port = chrome.runtime.connectNative(HOST);
    nativePort = port;
    port.onMessage.addListener(message => {
      if (port !== nativePort) return;
      const state = parseState(message);
      if (!state) {
        status.error = "ViewFit · 随屏返回了无效的缩放配置，请更新应用和扩展。";
        status.connected = false;
        status.state = null;
        controller.disconnect();
        refreshBadge();
        return;
      }
      status.connected = true;
      status.state = state;
      status.error = null;
      void controller.acceptState(state);
      refreshBadge();
    });
    port.onDisconnect.addListener(() => {
      // Consume lastError synchronously to avoid an unchecked Chrome error.
      const message = chrome.runtime.lastError?.message;
      if (port !== nativePort) return;
      nativePort = null;
      controller.disconnect();
      status.connected = false;
      status.state = null;
      status.error = message || "与 ViewFit · 随屏的连接已断开。";
      refreshBadge();
      void chrome.alarms.create(RECONNECT_ALARM, { delayInMinutes: 0.5 });
    });
    port.postMessage({ type: "getState" });
  } catch (error) {
    nativePort = null;
    controller.disconnect();
    status.connected = false;
    status.state = null;
    status.error = String(error.message || error);
    refreshBadge();
    void chrome.alarms.create(RECONNECT_ALARM, { delayInMinutes: 0.5 });
  }
}

chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === RECONNECT_ALARM) connect(); });
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.tabs.onCreated.addListener(tab => { void controller.applyTab(tab.id, true); });
chrome.tabs.onActivated.addListener(({ tabId }) => { connect(); void controller.applyTab(tabId); });
chrome.tabs.onUpdated.addListener((id, change) => {
  if (change.status === "loading" || change.status === "complete" || change.discarded === false) {
    void controller.applyTab(id, true);
  }
});
chrome.tabs.onRemoved.addListener(id => controller.forgetTab(id));
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id) return;
  if (message?.type === "status") { respond(status); return; }
  if (message?.type === "reconnect") {
    if (nativePort) {
      const oldPort = nativePort;
      nativePort = null;
      oldPort.disconnect();
    }
    controller.disconnect();
    status.connected = false;
    status.state = null;
    status.error = "正在连接 ViewFit · 随屏…";
    connect();
    respond(status);
  }
});
connect();
