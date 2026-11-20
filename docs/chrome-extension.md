# ViewFit · 随屏：Chrome 自动缩放

Chrome 的缩放是按页面／网站保存的。仅发送 `⌘+` 无法可靠覆盖后台标签页；ViewFit · 随屏因此附带一个本地 Chrome 扩展，由原生应用传入目标比例，扩展通过 Chrome 官方 `tabs.setZoom` 接口精确设置。

## 初次连接

1. 在「ViewFit · 随屏」设置中安装 Chrome 连接组件。
2. 打开 `chrome://extensions`，开启右上角「开发者模式」。
3. 选择「加载已解压的扩展程序」，选择应用提供的 `ChromeExtension` 文件夹。
4. 打开扩展的面板，确认显示「已连接 ViewFit · 随屏（本地组件）」，并在菜单栏应用中开启自动缩放。若刚安装连接组件，点一次「重新连接」。

扩展固定 ID 为 `fgmjjmcpabiopnbpgcjdbgfbcpiajmhl`。如果 Chrome 显示其他 ID，请确认加载的是随「ViewFit · 随屏」分发、保留 `manifest.json` 中 `key` 的完整文件夹。每个 Chrome 用户配置文件都需要启用此扩展。无痕模式需在扩展详情中由用户单独允许。

## 行为与边界

- 插拔显示器或修改配置后，更新所有已加载标签页；新标签页和导航后的页面也会应用规则。
- 外接屏的比例来自菜单栏应用；没有活动外接屏时固定使用 100%。当前版本按整台 Mac 的显示器配置切换，不区分同一时间放在内屏、外屏上的两个 Chrome 窗口。
- 使用 `automatic` + `per-tab` 缩放，不改写 Chrome 已保存的网站缩放偏好。页面导航后 Chrome 会重置该临时模式，扩展会重新应用。
- 用户手动调整当前页面后，会保留该调整直到下次页面导航或显示器／配置变化，不会持续和 `⌘+`／`⌘−` 对抗。
- 暂停、禁用 Chrome 支持或断开本地连接后，扩展停止调整，保留页面当前大小。
- `chrome://`、其他扩展页、Chrome 明确拒绝调整的页面会跳过；休眠／丢弃的标签页等到加载或激活后处理。内置 PDF 阅读器等特殊页面的缩放受 Chrome 自身限制。
- 没有网页内容脚本，没有网络请求，没有网页域名权限，也没有读取标题／历史记录的 `tabs` 权限。扩展只需要 `nativeMessaging` 和用于失败重连的 `alarms` 权限。

## 本地协议

为兼容已有安装，应用改名后仍保留原生主机名称 `com.avenry.screenscale` 与原有扩展 ID；这两个技术标识不影响界面名称。用户级注册文件：

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.avenry.screenscale.json
```

主机清单的 `allowed_origins` 为：

```json
["chrome-extension://fgmjjmcpabiopnbpgcjdbgfbcpiajmhl/"]
```

扩展通过 `runtime.connectNative` 建立长连接，发出：

```json
{"type":"getState"}
```

主机必须在连接建立时和状态改变时返回完整状态（`chromeZoom` 是倍数，`generation` 为安全整数）：

```json
{"enabled":true,"externalConnected":true,"chromeEnabled":true,"chromeZoom":1.25,"generation":1}
```

标准 Native Messaging 格式为：4 字节本机字节序长度 + UTF-8 JSON。主机日志只能写到 stderr，不能污染 stdout；stdin 关闭时应退出。原生端需要避免退出应用后仍广播旧的启用状态。扩展断连后用 Chrome alarm 在 30 秒后重试，点击面板中的「重新连接」可立即重试。

`ChromeExtension/tests/zoom-controller.test.mjs` 验证插拔恢复、精确比例、重复事件、导航、禁用、受限标签页与异步插拔竞态。运行：

```sh
node --test ChromeExtension/tests/zoom-controller.test.mjs
```

参考：[Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)、[Tabs API](https://developer.chrome.com/docs/extensions/reference/api/tabs)、[MV3 生命周期](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)。
