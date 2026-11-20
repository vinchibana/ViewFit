const byID = id => document.getElementById(id);

async function render() {
  try {
    const status = await chrome.runtime.sendMessage({ type: "status" });
    const state = status.state;
    byID("connection").textContent = status.connected ? "已连接 ViewFit · 随屏（本地组件）" : "尚未连接";
    byID("display").textContent = state ? (state.externalConnected ? "外接显示器" : "内置显示器") : "等待显示器配置";
    byID("zoom").textContent = state ? `${Math.round(state.chromeZoom * 100)}%` : "—";
    byID("detail").textContent = !status.connected
      ? "请打开 ViewFit · 随屏，并在设置中安装 Chrome 连接组件，然后重新连接。"
      : !state.enabled || !state.chromeEnabled
        ? "自动缩放未启用。请确认菜单栏应用正在运行，且 Chrome 自动缩放已开启。"
        : "已有网页和新打开的网页会跟随此比例。Chrome 系统页面可能不支持调整。";
    byID("error").hidden = !status.error;
    byID("error").textContent = status.error || "";
  } catch {
    byID("connection").textContent = "扩展连接已中断，请重新打开此面板。";
  }
}
byID("reconnect").addEventListener("click", async () => {
  await chrome.runtime.sendMessage({ type: "reconnect" });
  await render();
});
void render();
setInterval(render, 1000);
