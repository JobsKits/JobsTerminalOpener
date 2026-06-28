# `【MacOS】卸载用终端打开Finder扩展.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`【MacOS】卸载用终端打开Finder扩展.command` 用来卸载 `JobsTerminalOpener` 的 Finder Sync Extension，移除 Finder 右键菜单里的 `用终端打开` 入口，并清理旧 Automator 服务版残留。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 不再需要 Finder 右键 `用终端打开`。
- Finder 右键菜单中残留了旧扩展或旧 Automator 服务入口。
- 重新调试 `JobsTerminalOpener` 前，需要先清理旧注册状态和构建产物。

## 二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1. 在 Finder 中双击 `./【MacOS】卸载用终端打开Finder扩展.command`。
2. 终端会先展示脚本内置自述。
3. 确认影响范围后按回车继续；按 `Ctrl+C` 取消。
4. 脚本完成后会重启 Finder，用来刷新 Finder Sync Extension 菜单缓存。

也可以在终端中执行：

```shell
./【MacOS】卸载用终端打开Finder扩展.command
```

## 三、影响范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 禁用并注销 `com.jobs.JobsTerminalOpener.FinderSyncExtension`。
- 停止 `JobsTerminalOpener` 宿主 App 和 `JobsTerminalFinderSync` 扩展进程。
- 删除 [**Xcode**](https://developer.apple.com/xcode) DerivedData 中的 `JobsTerminalOpener.app` 构建产物。
- 删除本工程 `../work/JobsTerminalOpenerDerivedData` 旧构建产物。
- 删除系统临时目录中的 `JobsTerminalOpenerNeedsFinderRestart` 和 `JobsTerminalOpener.log`。
- 删除旧 Automator 服务 `用终端打开.workflow` 和辅助脚本 `OpenInTerminal.zsh`。
- 刷新 macOS Services 缓存并重启 Finder。
- 不删除上一级 `JobsTerminalOpener` 工程源码。

## 四、日志与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 脚本日志写入系统临时目录中的 `【MacOS】卸载用终端打开Finder扩展.log`。
- 如果脚本提示缺少命令，先确认当前系统是 macOS，并检查 `pluginkit`、`pkill`、`killall`、`find` 等系统命令是否可用。
- 如果菜单短时间仍显示，重新打开 Finder 窗口；必要时注销后重新登录。
- 以后重新运行 `JobsTerminalOpener.xcodeproj` 主 App 时，扩展会再次注册并启用。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
