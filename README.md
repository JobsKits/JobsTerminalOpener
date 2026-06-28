# `JobsTerminalOpener`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

![image-20260628203344107](./assets/image-20260628203344107.png)

`JobsTerminalOpener` 是一个 [**Swift**](https://www.swift.org/) macOS App + Finder Sync Extension 工程，用来把“用终端打开”放到 Finder 右键一级菜单区域。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在 Finder 中右键任意一个本地文件或文件夹。
- 点击一级右键菜单里的 `用终端打开`。
- 如果选中项是普通文件夹，会让系统 `Terminal.app` 新开窗口并 `cd` 到该文件夹。
- 如果选中项是文件或包文件，会让系统 `Terminal.app` 新开窗口并 `cd` 到它所在的父目录。
- 当前入口只处理单个选中项；多选时不展示菜单，避免打开结果不明确。

## 二、环境先决条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 检查项 | 要求 | 说明 |
| --- | --- | --- |
| 系统版本 | macOS `12.0` 及以上 | 工程 `MACOSX_DEPLOYMENT_TARGET` 为 `12.0`，功能依赖 Finder Sync Extension。 |
| 开发工具 | [**Xcode**](https://developer.apple.com/xcode) + `xcodebuild` | 手动运行用 Xcode；根目录批量安装脚本会调用 `xcodebuild` 构建主 App 和扩展。 |
| Finder 扩展 | 系统设置中启用 `用终端打开` | 构建阶段会注册并尝试启用扩展；如果菜单未出现，先确认系统设置里的 Finder 扩展开关。 |
| 终端程序 | 系统 `Terminal.app` | 宿主 App 会请求 Terminal 新开窗口并执行 `cd` 到目标目录；首次使用可能需要允许自动化控制 Terminal。 |
| 本地文件目标 | Finder 中只选中一个本地 `file://` 项目 | 多选、网络挂载异常、权限受限目录都可能让菜单不展示或打开失败。 |

建议运行前先做基础自检：

```shell
xcode-select -p
xcodebuild -version
pluginkit -m -p com.apple.FinderSync -A -v | grep JobsTerminalOpener
```

## 三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1. 用 [**Xcode**](https://developer.apple.com/xcode) 打开 `JobsTerminalOpener.xcodeproj`。
2. 选择 `JobsTerminalOpener` Scheme，直接运行主 App。
3. Xcode 构建阶段会自动注册宿主 App 的 `jobsterminalopener://` URL Scheme，停止旧的宿主 App / Finder Sync 扩展进程，注册并启用 `com.jobs.JobsTerminalOpener.FinderSyncExtension`，成功后会重启 Finder 刷新右键菜单缓存。
4. 回到 Finder，右键任意文件或文件夹，点击 `用终端打开`。
5. 首次重新安装后，构建阶段可能会等待几十秒，用来等 `pluginkit` 从空状态异步登记到可启用状态。

## 四、实现边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- Finder Sync Extension 可以进入 Finder 右键一级菜单区域，但最终位置由 macOS 决定，不能保证排在系统菜单项前面。
- 扩展默认监控 `/`，用于覆盖 Finder 中任意位置的文件和文件夹右键菜单。
- 扩展不读取文件内容，只读取 Finder 传入的本地 `file://` URL，并通过 `jobsterminalopener://open` 交给宿主 App 处理。
- 宿主 App 计算目标目录后，通过 `/usr/bin/osascript` 请求 `Terminal.app` 新开窗口并执行 `cd 目标目录`。
- 不生成临时 `.command` 脚本，因此新窗口不会显示 `$TMPDIR/JobsTerminalOpenerScripts/open-xxx.command ; exit;`。
- 新窗口由 `Terminal.app` 自己创建，会加载用户终端配置，并停在目标目录。
- 不复用正在执行任务的既有 Terminal 窗口；每次点击都会由 Terminal 新开一个窗口执行 `cd`。
- 宿主 App 通过 URL Scheme 被 Finder 扩展唤起时只处理打开目录请求，不再展示主窗口。
- Finder Sync Extension 保留 App Sandbox；本机自用版通过 `com.apple.security.temporary-exception.files.absolute-path.read-only` 给 `/` 增加只读例外。
- 菜单入口只在 Finder 选中单个本地项目时出现。

## 五、排查说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 右键菜单未出现：
  - 确认 `JobsTerminalFinderSync.entitlements` 保留了 `com.apple.security.app-sandbox`；Finder Sync Extension 去掉 sandbox 后可能无法被 `pluginkit` 登记出来。
  - 确认系统设置中 Finder 扩展已经启用，或点击 App 内的 `重新启用扩展`。
  - 重新打开 Finder 窗口。
  - 重新编译后构建阶段会重新启用扩展，并自动重启 Finder。
  - 也可以执行下面命令确认扩展已启用，输出行前面有 `+` 表示启用：

    ```shell
    pluginkit -m -p com.apple.FinderSync -A -v | grep JobsTerminalOpener
    ```

  - 如果已经注册但没有 `+`，执行下面命令启用：

    ```shell
    pluginkit -e use -i com.jobs.JobsTerminalOpener.FinderSyncExtension
    ```

- 点击后没有打开 Terminal：
  - 确认 Finder 中只选中了一个本地文件或文件夹。
  - 确认系统存在 `Terminal.app`。
  - 确认 `JobsTerminalFinderSync.entitlements` 里有 `com.apple.security.temporary-exception.files.absolute-path.read-only`，并包含 `/`。
  - 修改 entitlements 后必须重新运行 `JobsTerminalOpener.xcodeproj` 主 App，让扩展重新签名、注册并启用。
  - 确认菜单来自 `JobsTerminalOpener`，不是旧服务或其它同名工具。
  - 如果扩展日志里没有 `request terminal open via`，说明当前点击没有进入新版扩展；重新构建并确认 `pluginkit` 指向最新 `JobsTerminalFinderSync.appex`。
  - 如果扩展日志里已经有 `delegate terminal open request accepted`，但 `/tmp/JobsTerminalOpener.log` 没有 `application open urls=`，说明 URL Scheme 没有被当前宿主 App 接管；重新运行主 App 或重新构建。
  - 如果系统临时目录中的 `JobsTerminalOpener.log` 已经出现 `terminal cd directory exit=0`，但新窗口停在错误目录，优先确认正在运行的是新版构建，并检查 Finder 选中项是否为目标文件或文件夹。
  - 如果新窗口仍显示临时 `.command ; exit;`，说明 Finder 仍在调用旧版构建产物；重新构建、注册并重启 Finder。
  - 重新点击 App 内的 `重新启用扩展`，再重启 Finder。

- 查看扩展调试日志：

  ```shell
  log stream --predicate 'process == "JobsTerminalFinderSync"' --style compact
  ```

  ```shell
  tail -n 200 "$HOME/Library/Containers/com.jobs.JobsTerminalOpener.FinderSyncExtension/Data/Library/Application Support/JobsTerminalFinderSync/FinderSync.log"
  ```

  ```shell
  tail -n 200 "/tmp/JobsTerminalOpener.log"
  ```

  扩展日志重点看 `request terminal open via` 和 `delegate terminal open request accepted`；宿主 App 日志重点看 `application open urls=`、`terminal target directory=`、`terminal cd directory exit=` 和 `terminal activate attempt=`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
