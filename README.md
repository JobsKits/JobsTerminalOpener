# `JobsTerminalOpener`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

> **本工程内含 5 个可独立勾选的 Finder 右键功能：`用终端打开`｜`pod install`｜`flutter pub get`｜`CodeGraph 代码地图`｜`空白 Commit 并 Push`。**

![image-20260628203344107](./assets/image-20260628203344107.png)

`JobsTerminalOpener` 是一个 [**Swift**](https://www.swift.org/) macOS App + Finder Sync Extension 工程。五项功能共用一个扩展，首次安装时可以逐项勾选；安装完成后也能直接在 App 内查看和修改五项功能，不需要重新编译。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在 Finder 中右键任意一个本地文件或文件夹。
- 点击一级右键菜单里的 `用终端打开`。
- 如果选中项是普通文件夹，会让系统 `Terminal.app` 新开窗口并 `cd` 到该文件夹。
- 如果选中项是文件或包文件，会让系统 `Terminal.app` 新开窗口并 `cd` 到它所在的父目录。
- 当前文件夹直接包含 `Podfile` 和至少一个 `*.xcodeproj` 时，显示 `在终端执行 pod install`，让 `Terminal.app` 新开窗口并在该目录执行 `pod install`。
- 当前文件夹直接包含 `pubspec.yaml`、`lib/`，且清单声明 `sdk: flutter` 时，显示 `在终端执行 flutter pub get`，让 `Terminal.app` 新开窗口并在该目录执行 `flutter pub get`。
- 右键普通文件夹时，显示 `安装/升级 CodeGraph 代码地图`，让 `Terminal.app` 新开窗口并完成 CodeGraph 命令自检、安装或升级，以及当前文件夹代码地图的初始化或同步。
- 右键普通文件夹时，显示 `在终端创建空白 Commit 并 Push`；Terminal 会校验 Git、工作树、当前分支、暂存区和推送远程，通过后创建 `chore: empty commit` 空白提交并 Push。
- 依赖操作不会向父目录或子目录递归查找工程；右键位置不是对应工程的标准根目录时，不显示相关入口。
- 当前入口只处理单个选中项；多选时不展示菜单，避免打开结果不明确。

## 二、环境先决条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 检查项 | 要求 | 说明 |
| --- | --- | --- |
| 系统版本 | macOS `12.0` 及以上 | 工程 `MACOSX_DEPLOYMENT_TARGET` 为 `12.0`，功能依赖 Finder Sync Extension。 |
| 开发工具 | [**Xcode**](https://developer.apple.com/xcode) + `xcodebuild` | 手动运行用 Xcode；根目录批量安装脚本会调用 `xcodebuild` 构建主 App 和扩展。 |
| Finder 扩展 | 系统设置中启用 `用终端打开` | 构建阶段会注册并尝试启用扩展；如果菜单未出现，先确认系统设置里的 Finder 扩展开关。 |
| 终端程序 | 系统 `Terminal.app` | 宿主 App 会请求 Terminal 新开窗口并执行 `cd` 到目标目录；首次使用可能需要允许自动化控制 Terminal。 |
| [**CocoaPods**](https://cocoapods.org/) | 终端环境可执行 `pod` | 只有使用 `pod install` 入口时需要；命令不可用时，Terminal 会直接显示错误。 |
| [**Flutter**](https://flutter.dev/) | 终端环境可执行 `flutter` | 只有使用 `flutter pub get` 入口时需要；命令不可用时，Terminal 会直接显示错误。 |
| [**CodeGraph**](https://github.com/colbymchenry/codegraph) | 系统 `/bin/bash` 和 `curl` 可用 | 操作会逐级自检 CodeGraph、npm、Node.js 和 Homebrew；缺失 npm 时通过 Homebrew 安装 Node.js，缺失 Homebrew 时运行官方安装器。 |
| Git 空白推送 | 终端环境可执行 `git` | 当前文件夹必须在 Git 工作树内，当前分支可推送，且暂存区必须为空。 |
| 本地文件目标 | Finder 中只选中一个本地 `file://` 项目 | 多选、网络挂载异常、权限受限目录都可能让菜单不展示或打开失败。 |

建议运行前先做基础自检：

```shell
xcode-select -p
xcodebuild -version
pluginkit -m -p com.apple.FinderSync -A -v | grep JobsTerminalOpener
pod --version
flutter --version
brew --version
node --version
npm --version
codegraph --version
git --version
```

## 三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 3.1、原生 UI 勾选安装

1、双击上级目录的 `../【MacOS】🧩安装Finder扩展.command`。

2、阅读脚本自述并按回车，随后在 macOS 原生复选框窗口中逐项选择右键菜单功能，或点击“全部安装”。

3、`JobsTerminalOpener` 的五项功能会归并为一次工程构建；安装器同时保存这五项的初始选择。

4、需要更换功能组合时，可以重新运行安装脚本，也可以直接在已安装 App 内修改。

### 3.2、App 内查看和修改功能

1、打开 `JobsTerminalOpener` App，窗口中的“可选功能”区域会把五项功能各列一行。

2、复选框会显示当前生效状态；可以逐项勾选，也可以点击“全部选择”或“全部取消”。

3、点击“保存功能选择”。Finder 扩展会在下一次生成右键菜单时读取新配置，关闭当前菜单并重新右键即可生效。

4、项目条件校验仍然有效：例如启用 `pod install` 后，当前目录没有 `Podfile` 和 `*.xcodeproj` 时仍不会显示该入口。

### 3.3、Xcode 手动运行

1、用 [**Xcode**](https://developer.apple.com/xcode) 打开 `JobsTerminalOpener.xcodeproj`。

2、选择 `JobsTerminalOpener` Scheme，直接运行主 App。

3、Xcode 构建阶段会自动注册宿主 App 的 `jobsterminalopener://` URL Scheme，停止旧的宿主 App / Finder Sync 扩展进程，注册并启用 `com.jobs.JobsTerminalOpener.FinderSyncExtension`，成功后会重启 Finder 刷新右键菜单缓存。

4、如果本机还没有保存过功能选择，手动构建默认启用全部五项功能；已有保存记录时继续沿用 App 中的选择。回到 Finder，右键任意文件或文件夹即可使用符合当前目录条件的菜单入口。

5、首次重新安装后，构建阶段可能会等待几十秒，用来等 `pluginkit` 从空状态异步登记到可启用状态。

## 四、实现边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- Finder Sync Extension 可以进入 Finder 右键一级菜单区域，但最终位置由 macOS 决定，不能保证排在系统菜单项前面。
- 五项 Terminal 功能当前共用一个宿主 App 和一个 Finder Sync Extension；安装 UI 与宿主 App 都把它们作为五个独立菜单功能选择。
- `JobsTerminalEnabledFeatures` 提供首次运行的构建默认值；安装器或 App 保存过选择后，Finder 扩展每次生成右键菜单都会优先读取本机配置，因此后续修改不需要重新构建。
- 扩展默认监控 `/`，用于覆盖 Finder 中任意位置的文件和文件夹右键菜单。
- 扩展不读取文件内容，只读取 Finder 传入的本地 `file://` URL，并通过 `jobsterminalopener://open` 把路径和动作类型交给宿主 App 处理。
- Finder 扩展和宿主 App 对 CocoaPods、Flutter 和 CodeGraph 共用目标类型校验；Git 管理状态、暂存区和远程信息则按“所有走终端”的边界，在 Terminal 内执行前现场校验。
- CocoaPods iOS 工程只认当前目录直接存在的 `Podfile` 和 `*.xcodeproj`；Flutter 工程只认当前目录直接存在的 `pubspec.yaml`、`lib/` 和清单中的 `sdk: flutter` 声明。
- CodeGraph 入口只对普通文件夹显示并执行；文件、Finder 包文件和其它非目录目标不显示入口，宿主 App 执行前也会再次拒绝。
- 空白 Commit 入口同样只对普通文件夹显示。是否由 Git 管理不在 Finder 进程中预判；点击后由 Terminal 运行 `git rev-parse --is-inside-work-tree` 校验当前文件夹，非 Git 目录只输出错误并停止。
- 宿主 App 计算目标目录后，通过 `/usr/bin/osascript` 请求 `Terminal.app` 新开窗口；普通入口执行 `cd 目标目录`，iOS 依赖入口执行 `cd 目标目录 && pod install`，Flutter 依赖入口执行 `cd 目标目录 && flutter pub get`。
- 空白 Commit 入口会先确认 Git 命令健康、当前目录在工作树内、当前处于正常分支、暂存区为空，并能确定上游或唯一推送远程。然后执行 `git commit --allow-empty -m 'chore: empty commit'` 和 `git push`；无上游时优先使用 `origin`，否则只在存在唯一远程时为当前分支建立上游。Push 失败时空白 Commit 保留在本地，Terminal 会打印提交哈希。
- CodeGraph 入口按 `npm/Node.js → Homebrew → bash/curl/Command Line Tools` 向上溯源：每一级都同时检查命令是否存在、版本命令是否能正常运行；npm 或 Node.js 不可用时，通过 Homebrew 安装或修复 `node`；Homebrew 不可用时，下载并运行官方安装器，安装过程中可能要求管理员密码并引导安装 Command Line Tools。系统 `/bin/bash` 或 `curl` 不可用时无法继续自动引导，会在 Terminal 中明确报错并停止。
- npm 就绪后再检查 CodeGraph：命令可用时只尝试 `codegraph upgrade`，升级失败则保留当前版本继续；命令缺失或损坏时执行 `npm install -g @colbymchenry/codegraph@latest`。最后，当前文件夹已有 `.codegraph/` 就执行 `codegraph sync .`，否则执行 `codegraph init --yes .`，并输出 `codegraph status .`。
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
  - 如果系统临时目录中的 `JobsTerminalOpener.log` 已经出现 `terminal command exit=0`，但新窗口停在错误目录，优先确认正在运行的是新版构建，并检查 Finder 选中项是否为目标文件或文件夹。
  - 如果新窗口仍显示临时 `.command ; exit;`，说明 Finder 仍在调用旧版构建产物；重新构建、注册并重启 Finder。
  - 重新点击 App 内的 `重新启用扩展`，再重启 Finder。

- 依赖操作没有出现在右键菜单：
  - 先打开 `JobsTerminalOpener` App，确认对应功能已勾选并点击“保存功能选择”；也可以重新运行上级安装脚本改变初始组合。
  - `pod install`：确认右键的当前文件夹直接包含 `Podfile` 和至少一个 `*.xcodeproj`。
  - `flutter pub get`：确认右键的当前文件夹直接包含 `pubspec.yaml`、`lib/`，并且 `pubspec.yaml` 中存在有效的 `sdk: flutter` 声明。
  - Finder 菜单打开后才补齐文件不会实时刷新当前菜单；关闭菜单后重新右键。

- CodeGraph 操作没有出现在右键菜单：
  - 确认右键目标是普通文件夹，不是文件、`*.xcodeproj` 等 Finder 包文件或多选目标。
  - 首次安装会自动检查并补齐 npm、Node.js 和 Homebrew；如果需要新装 Homebrew，Terminal 可能要求管理员密码并安装 Command Line Tools。
  - `/bin/bash` 或系统 `curl` 属于自动引导的最上游条件；它们不可用时，Terminal 会打印具体错误并停止，不会继续初始化项目。
  - 如果 `codegraph upgrade` 因网络或安装权限失败，Terminal 会保留完整输出并继续尝试使用当前版本；只有 `codegraph` 命令最终不可用时才会停止。

- 空白 Commit 并 Push 失败：
  - 确认右键目标是普通文件夹，且当前文件夹位于 Git 工作树内。
  - 暂存区有内容时会主动停止，避免把文件变更带入空白 Commit；先处理或取消暂存内容后再执行。
  - detached HEAD、无上游且远程不唯一、Git 用户信息未配置或网络鉴权失败都会保留明确的 Terminal 输出。
  - Commit 已创建但 Push 失败时，不自动回滚本地历史；根据 Terminal 打印的哈希修复远程或鉴权后重新 Push。

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

  扩展日志重点看 `action=`、`request terminal open via` 和 `delegate terminal open request accepted`；宿主 App 日志重点看 `application open urls=`、`terminal action=`、`terminal command exit=` 和 `terminal activate attempt=`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
