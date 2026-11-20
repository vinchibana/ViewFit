# ViewFit · 随屏

**换个屏幕，大小刚好。**

Swift / SwiftUI 菜单栏应用。连接外接显示器时使用各应用的预设，拔掉后恢复 Chrome、Codex 的 100%，微信恢复基准字号。

## 使用

1. 打开 `ViewFit.app`，菜单栏出现文字大小图标；首次启动显示设置。
2. 给 ViewFit · 随屏 开启「系统设置 → 隐私与安全性 → 辅助功能」。只需授权 ViewFit，无需授权终端或其他工具。
3. 设置 Chrome、Codex 的外接屏比例，以及微信的原生放大档位。
4. Chrome 首次连接：在设置里依次点击「安装连接组件」「显示扩展文件夹」「打开扩展管理」。在 `chrome://extensions` 开启开发者模式，加载该文件夹。每个 Chrome profile 需要分别加载一次。
5. 可选开启「登录 Mac 时启动」。

**先把应用放到最终位置，再安装 Chrome 连接组件。** 移动应用后重新点击安装组件，并重新加载扩展。

## 行为与边界

- 根据系统提供的显示器类型选择配置，不依赖屏幕数量。合盖外屏、镜像显示属于设计支持范围，仍需实机验证。AirPlay、Sidecar、虚拟屏也会被视作外接屏。
- 当前为全局「有外接屏 / 只有内屏」两套配置；不根据每个窗口所在显示器分别缩放。外接屏存在时，内屏上的受控应用也使用外接预设。
- 显示变化防抖 1.2 秒，唤醒重新检查；重复通知不会累计放大。
- **Chrome：** 本地扩展通过浏览器 API 设置每个标签页的精确比例；覆盖现有网页和新打开/导航的网页。内部页面等不允许缩放的页面跳过。使用 per-tab scope，不改写网站保存的缩放偏好。自动化未暂停时，新导航继续应用预设；当前页的临时手动缩放保留到下一次导航或配置变化。
- **Codex：** 支持 100–200%，每档 10%。切回前台时操作原生缩放菜单；不抢焦点。当前版本的菜单会根据焦点改变内置浏览器或整个应用的缩放；检测到聚焦网页时会停止本次调整；点击对话区域后，可在菜单栏点「应用当前规则」重试。该检测无法保证识别所有内嵌浏览器状态。
- **微信：** 当前只确认原生「放大 / 缩小」档位，没有可靠百分比接口。提供基准、放大一档、放大两档。基准定义为「缩小菜单不再可用」的最小原生档位，不能宣称精确等于100%。切回前台时通过定向快捷键先回基准，再应用预设，不打开顶部菜单。单次回基准最多缩小两档；若手动放大超过两档或微信状态无法验证，则停止并显示错误，不盲目继续按键。
- **失败即停止：** 同一个显示器配置下，一次调整失败后，定时器和应用切换都不会自动重试。点击「应用当前规则」、修改配置或真正切换显示器配置，才会发起新的尝试。执行中切换前台应用也会停止本次操作。
- 暂停或退出保留当前缩放，不恢复原先任意手动值；重新启用后应用当前配置。
- Chrome host 在应用异常退出、状态20秒未刷新后停止提供有效启用配置。
- **开发预览状态：** 尚未完成真实显示器插拔、合盖和睡眠恢复的整链路验收。微信改用定向快捷键后的实际缩放送达与持续前台观察也未完成，不能把自动化测试通过等同于实机验证通过。

## 数据和权限

没有云服务、网络请求、分析上报或用户内容日志。配置存在 `~/Library/Application Support/ScreenScale/`。

Chrome 扩展只声明 `nativeMessaging`、`alarms` 权限；没有网页内容脚本、网站访问权限、历史记录权限。原生 host 只读取本地缩放状态，不执行扩展传来的脚本或命令。

Chrome Native Messaging 注册文件：`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.avenry.screenscale.json`。

为兼容早期版本，内部应用标识、配置目录和 Native Messaging 主机名保留 `ScreenScale` / `screenscale`；显示名称统一为 ViewFit · 随屏，现有配置和扩展 ID 不变。

这是本机 ad-hoc 签名开发版，没有公证或正式分发签名。修改代码并重签名后，macOS 可能要求重新授权辅助功能。

## 构建和测试

要求 macOS 14+、安装带 Swift 的 Xcode。运行扩展测试还需要 Node.js，运行本地通信集成测试需要 Python 3。应用无需第三方依赖。

```sh
bash scripts/build.sh
swift test --disable-sandbox
node --test ChromeExtension/tests/*.test.mjs
python3 scripts/test-bridge.py build/ViewFit.app/Contents/MacOS/ViewFitBridge
```

产物：`build/ViewFit.app` 和 `build/ViewFit.zip`。可直接在 Xcode 中打开 `Package.swift` 修改和调试；打包脚本生成完整菜单栏应用及 Chrome 本地 helper。

已有 18 项 Swift 测试、7 项 Chrome 扩展测试和 4 项本地通信集成检查，用于覆盖配置、失败锁定、微信有界缩放序列和消息协议。详见 [验证范围](docs/app-adapter-validation.md) 与 [Chrome 扩展说明](docs/chrome-extension.md)。

## 卸载

退出 ViewFit，关闭其登录启动；从 Chrome 移除 ViewFit · 随屏 扩展。将应用和上述配置目录、专属 Native Messaging 注册文件移至废纸篓即可。无需修改 Chrome 主配置或网站数据。
