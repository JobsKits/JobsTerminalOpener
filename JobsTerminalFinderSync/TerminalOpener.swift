//
//  TerminalOpener.swift
//  JobsTerminalFinderSync
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit

struct TerminalOpener {
    enum Action: String {
        case open
        case podInstall = "pod-install"
        case flutterPubGet = "flutter-pub-get"
        case codeGraphBootstrap = "codegraph-bootstrap"
        case gitEmptyCommitPush = "git-empty-commit-push"
    }

    private let dependencyProjectValidator = DependencyProjectValidator()
    private let writeLog: (String) -> Void

    init(writeLog: @escaping (String) -> Void = { _ in }) {
        self.writeLog = writeLog
    }

    func openTerminal(from fileURL: URL, action: Action) throws -> URL {
        let standardizedURL = fileURL.standardizedFileURL
        guard standardizedURL.isFileURL else {
            throw TerminalOpenError.unsupportedURL(fileURL)
        }

        let directoryURL = try terminalWorkingDirectory(from: standardizedURL, action: action)
        try runTerminalCommand(directoryURL: directoryURL, action: action)
        return directoryURL
    }
}

private extension TerminalOpener {
    enum TerminalOpenError: LocalizedError {
        case unsupportedURL(URL)
        case missingTerminal
        case invalidCocoaPodsProject(URL)
        case invalidFlutterProject(URL)
        case invalidCodeGraphTargetFolder(URL)
        case invalidGitEmptyCommitPushTargetFolder(URL)
        case terminalCommandFailed(String)

        var errorDescription: String? {
            switch self {
            /// 请求目标不是本地文件 URL
            case .unsupportedURL(let url):
                return "不是本地文件路径：\(url.absoluteString)"
            /// 系统没有安装 Terminal.app
            case .missingTerminal:
                return "没有找到系统 Terminal.app"
            /// pod install 请求目标不是合法的 CocoaPods iOS 工程目录
            case .invalidCocoaPodsProject(let url):
                return "当前文件夹不是合法的 CocoaPods iOS 工程目录，需要同时存在 Podfile 和 *.xcodeproj：\(url.path)"
            /// flutter pub get 请求目标不是合法的 Flutter 工程目录
            case .invalidFlutterProject(let url):
                return "当前文件夹不是合法的 Flutter 工程目录，需要存在 pubspec.yaml、lib/，且清单声明 sdk: flutter：\(url.path)"
            /// CodeGraph 请求目标不是普通文件夹
            case .invalidCodeGraphTargetFolder(let url):
                return "CodeGraph 只能安装到普通文件夹：\(url.path)"
            /// 空白 Commit 与 Push 请求目标不是普通文件夹
            case .invalidGitEmptyCommitPushTargetFolder(let url):
                return "空白 Commit 并 Push 只能对普通文件夹执行：\(url.path)"
            /// 请求 Terminal.app 执行命令失败
            case .terminalCommandFailed(let message):
                return message
            }
        }
    }

    func terminalWorkingDirectory(from fileURL: URL, action: TerminalOpener.Action) throws -> URL {
        switch action {
        /// 普通打开终端时，文件或包文件使用父目录
        case .open:
            if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
               values.isDirectory == true,
               values.isPackage != true {
                return fileURL
            };return fileURL.deletingLastPathComponent()
        /// pod install 只允许在合法的 CocoaPods iOS 工程目录执行
        case .podInstall:
            guard dependencyProjectValidator.isCocoaPodsProject(at: fileURL) else {
                throw TerminalOpenError.invalidCocoaPodsProject(fileURL)
            };return fileURL
        /// flutter pub get 只允许在合法的 Flutter 工程目录执行
        case .flutterPubGet:
            guard dependencyProjectValidator.isFlutterProject(at: fileURL) else {
                throw TerminalOpenError.invalidFlutterProject(fileURL)
            };return fileURL
        /// CodeGraph 只允许在普通文件夹中安装或升级
        case .codeGraphBootstrap:
            guard dependencyProjectValidator.isCodeGraphTargetFolder(at: fileURL) else {
                throw TerminalOpenError.invalidCodeGraphTargetFolder(fileURL)
            };return fileURL
        /// 空白 Commit 与 Push 的 Git 管理状态会在 Terminal 内校验
        case .gitEmptyCommitPush:
            guard dependencyProjectValidator.isGitEmptyCommitPushTargetFolder(at: fileURL) else {
                throw TerminalOpenError.invalidGitEmptyCommitPushTargetFolder(fileURL)
            };return fileURL
        }
    }

    func runTerminalCommand(directoryURL: URL, action: TerminalOpener.Action) throws {
        let terminalURL = try terminalApplicationURL()

        writeLog("terminal action=\(action.rawValue), target directory=\(directoryURL.path)")
        writeLog("terminal app=\(terminalURL.path)")
        try openDirectoryInTerminal(directoryURL, action: action)
        activateTerminalWhenAvailable()
    }

    func terminalApplicationURL() throws -> URL {
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return terminalURL
        }

        let candidateURLs = [
            URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities/Terminal.app", isDirectory: true)
        ]

        for candidateURL in candidateURLs where FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        throw TerminalOpenError.missingTerminal
    }

    func terminalRunningApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first
    }

    func openDirectoryInTerminal(_ directoryURL: URL, action: TerminalOpener.Action) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            terminalOpenAppleScript(),
            directoryURL.path,
            action.rawValue,
            gitEmptyCommitPushCommand()
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw TerminalOpenError.terminalCommandFailed("请求 Terminal.app 执行命令失败：\(error.localizedDescription)")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        writeLog("terminal command exit=\(process.terminationStatus), output=\(output)")
        guard process.terminationStatus == 0 else {
            throw TerminalOpenError.terminalCommandFailed("Terminal.app 执行命令失败：\(output)")
        }
    }

    func terminalOpenAppleScript() -> String {
        """
        on run argv
            set targetPath to item 1 of argv
            set terminalAction to item 2 of argv
            set emptyCommitPushCommand to item 3 of argv
            set terminalCommand to "cd " & quoted form of targetPath
            if terminalAction is "pod-install" then
                set terminalCommand to terminalCommand & " && pod install"
            else if terminalAction is "flutter-pub-get" then
                set terminalCommand to terminalCommand & " && flutter pub get"
            else if terminalAction is "codegraph-bootstrap" then
                set codeGraphCommand to "codegraph_find_brew() { CODEGRAPH_BREW_CANDIDATE=$(command -v brew 2>/dev/null || true); if [ x${CODEGRAPH_BREW_CANDIDATE:-} != x ] && ${CODEGRAPH_BREW_CANDIDATE} --version >/dev/null 2>&1; then printf '%s\n' ${CODEGRAPH_BREW_CANDIDATE}; elif [ -x /opt/homebrew/bin/brew ] && /opt/homebrew/bin/brew --version >/dev/null 2>&1; then printf '%s\n' /opt/homebrew/bin/brew; elif [ -x /usr/local/bin/brew ] && /usr/local/bin/brew --version >/dev/null 2>&1; then printf '%s\n' /usr/local/bin/brew; else return 1; fi; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_find_curl() { CODEGRAPH_CURL_BIN=$(command -v curl 2>/dev/null || true); if [ x${CODEGRAPH_CURL_BIN:-} != x ] && ${CODEGRAPH_CURL_BIN} --version >/dev/null 2>&1; then return 0; elif [ -x /usr/bin/curl ] && /usr/bin/curl --version >/dev/null 2>&1; then CODEGRAPH_CURL_BIN=/usr/bin/curl; return 0; else CODEGRAPH_CURL_BIN=; return 1; fi; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_install_homebrew() { if [ ! -x /bin/bash ]; then printf '\n✖ 系统 /bin/bash 不可用，无法启动 Homebrew 官方安装器。\n'; return 1; fi; if ! codegraph_find_curl; then printf '\n✖ 系统 curl 不可用，无法下载 Homebrew 官方安装器。\n'; return 1; fi; if [ ! -x /usr/bin/xcode-select ] || ! /usr/bin/xcode-select -p >/dev/null 2>&1; then printf '\n▶ 未检测到 Command Line Tools，Homebrew 官方安装器将继续检查并引导安装。\n'; fi; CODEGRAPH_HOMEBREW_INSTALLER=$(mktemp ${TMPDIR:-/tmp}/JobsTerminalOpener-Homebrew.XXXXXX) || { printf '\n✖ 无法创建 Homebrew 安装器临时文件。\n'; return 1; }; printf '\n▶ 正在下载 Homebrew 官方安装器...\n'; if ! ${CODEGRAPH_CURL_BIN} -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o ${CODEGRAPH_HOMEBREW_INSTALLER}; then /bin/rm -f ${CODEGRAPH_HOMEBREW_INSTALLER}; printf '\n✖ Homebrew 官方安装器下载失败。\n'; return 1; fi; printf '▶ 即将运行 Homebrew 官方安装器；期间可能要求管理员密码并安装 Command Line Tools。\n'; /bin/bash ${CODEGRAPH_HOMEBREW_INSTALLER}; CODEGRAPH_HOMEBREW_INSTALL_STATUS=$?; /bin/rm -f ${CODEGRAPH_HOMEBREW_INSTALLER}; if [ ${CODEGRAPH_HOMEBREW_INSTALL_STATUS} -ne 0 ]; then printf '\n✖ Homebrew 安装失败，退出码：%s\n' ${CODEGRAPH_HOMEBREW_INSTALL_STATUS}; return ${CODEGRAPH_HOMEBREW_INSTALL_STATUS}; fi; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_ensure_brew() { CODEGRAPH_BREW_BIN=$(codegraph_find_brew 2>/dev/null || true); if [ x${CODEGRAPH_BREW_BIN:-} = x ]; then printf '\n▶ 未检测到可用的 Homebrew，开始向上检查系统安装条件...\n'; codegraph_install_homebrew || return 1; CODEGRAPH_BREW_BIN=$(codegraph_find_brew 2>/dev/null || true); fi; if [ x${CODEGRAPH_BREW_BIN:-} = x ]; then printf '\n✖ Homebrew 安装后仍不可用。\n'; return 1; fi; CODEGRAPH_BREW_PREFIX=$(${CODEGRAPH_BREW_BIN} --prefix 2>/dev/null) || { printf '\n✖ 无法读取 Homebrew 安装目录。\n'; return 1; }; export PATH=${CODEGRAPH_BREW_PREFIX}/bin:${CODEGRAPH_BREW_PREFIX}/sbin:${PATH}; rehash 2>/dev/null || true; printf '\n✔ Homebrew 可用：'; ${CODEGRAPH_BREW_BIN} --version | head -n 1; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_has_npm() { command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_ensure_npm() { if codegraph_has_npm; then printf '\n✔ Node.js 可用：'; node --version; printf '✔ npm 可用：'; npm --version; return 0; fi; printf '\n▶ npm 或 Node.js 不存在或不可用，继续向上检查 Homebrew...\n'; codegraph_ensure_brew || return 1; if codegraph_has_npm; then printf '✔ 加载 Homebrew 环境后 Node.js 可用：'; node --version; printf '✔ npm 可用：'; npm --version; return 0; fi; if ${CODEGRAPH_BREW_BIN} list --formula node >/dev/null 2>&1; then printf '\n▶ Homebrew 已登记 Node.js，但 npm 仍不可用，正在重新安装 Node.js...\n'; ${CODEGRAPH_BREW_BIN} reinstall node || return 1; else printf '\n▶ 正在通过 Homebrew 安装 Node.js（包含 npm）...\n'; ${CODEGRAPH_BREW_BIN} install node || return 1; fi; CODEGRAPH_BREW_PREFIX=$(${CODEGRAPH_BREW_BIN} --prefix 2>/dev/null) || return 1; export PATH=${CODEGRAPH_BREW_PREFIX}/bin:${CODEGRAPH_BREW_PREFIX}/sbin:${PATH}; rehash 2>/dev/null || true; if ! codegraph_has_npm; then printf '\n✖ Node.js 安装或修复后，node/npm 仍不可用。\n'; return 1; fi; printf '\n✔ Node.js 已就绪：'; node --version; printf '✔ npm 已就绪：'; npm --version; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_ensure_cli() { if command -v codegraph >/dev/null 2>&1 && codegraph --version >/dev/null 2>&1; then printf '\n✔ CodeGraph 可用，当前版本：'; codegraph --version; printf '▶ 正在尝试升级 CodeGraph...\n'; if codegraph upgrade; then printf '\n✔ CodeGraph 升级检查完成。\n'; else printf '\n⚠ CodeGraph 升级失败，将使用当前可用版本继续建立代码地图。\n'; fi; return 0; fi; printf '\n▶ CodeGraph 不存在或不可用，正在通过 npm 安装最新版...\n'; npm install -g @colbymchenry/codegraph@latest || return 1; CODEGRAPH_NPM_PREFIX=$(npm prefix -g 2>/dev/null) || { printf '\n✖ 无法读取 npm 全局安装目录。\n'; return 1; }; export PATH=${CODEGRAPH_NPM_PREFIX}/bin:${PATH}; rehash 2>/dev/null || true; if ! command -v codegraph >/dev/null 2>&1 || ! codegraph --version >/dev/null 2>&1; then printf '\n✖ CodeGraph 安装后仍不可用。\n'; return 1; fi; printf '\n✔ CodeGraph 已就绪：'; codegraph --version; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_prepare_project() { if [ -d .codegraph ]; then printf '\n▶ 已存在项目代码地图，执行增量同步...\n'; codegraph sync . || return 1; else printf '\n▶ 正在为当前文件夹创建代码地图...\n'; codegraph init --yes . || return 1; fi; printf '\n✔ 当前项目 CodeGraph 状态：\n'; codegraph status .; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_ensure_npm && codegraph_ensure_cli && codegraph_prepare_project"
                set terminalCommand to terminalCommand & " && " & codeGraphCommand
            else if terminalAction is "git-empty-commit-push" then
                set terminalCommand to terminalCommand & " && " & emptyCommitPushCommand
            end if
            tell application "Terminal"
                activate
                do script terminalCommand
            end tell
        end run
        """
    }

    func gitEmptyCommitPushCommand() -> String {
        #"""
        git_empty_commit_push() {
          local git_bin=""
          local inside_work_tree=""
          local repository_root=""
          local current_branch=""
          local upstream=""
          local push_remote=""
          local remote_count="0"
          local index_status="0"
          local commit_hash=""

          printf '\n▶ 正在检查当前文件夹是否由 Git 管理：%s\n' "$PWD"
          git_bin="$(command -v git 2>/dev/null || true)"
          if [[ -z "$git_bin" ]] || ! "$git_bin" --version >/dev/null 2>&1; then
            printf '✖ 未找到可用的 Git，已停止。\n'
            return 1
          fi
          printf '✔ Git 可用：'
          "$git_bin" --version

          inside_work_tree="$("$git_bin" rev-parse --is-inside-work-tree 2>/dev/null || true)"
          if [[ "$inside_work_tree" != "true" ]]; then
            printf '✖ 当前文件夹不在 Git 工作树内，不会创建 Commit：%s\n' "$PWD"
            return 1
          fi

          repository_root="$("$git_bin" rev-parse --show-toplevel 2>/dev/null || true)"
          current_branch="$("$git_bin" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          if [[ -z "$repository_root" ]]; then
            printf '✖ 无法读取 Git 仓库根目录，已停止。\n'
            return 1
          fi
          if [[ -z "$current_branch" ]]; then
            printf '✖ 当前处于 detached HEAD，不会创建或推送空白 Commit。\n'
            return 1
          fi
          printf '✔ Git 仓库：%s\n' "$repository_root"
          printf '✔ 当前分支：%s\n' "$current_branch"

          "$git_bin" diff --cached --quiet --
          index_status=$?
          if (( index_status == 1 )); then
            printf '✖ 暂存区存在待提交内容。为保证这次是纯空白 Commit，已停止。\n'
            return 1
          fi
          if (( index_status != 0 )); then
            printf '✖ 无法校验 Git 暂存区，已停止。\n'
            return "$index_status"
          fi
          printf '✔ 暂存区为空，不会带入文件改动。\n'

          upstream="$("$git_bin" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
          if [[ -z "$upstream" ]]; then
            if "$git_bin" remote get-url origin >/dev/null 2>&1; then
              push_remote="origin"
            else
              remote_count="$("$git_bin" remote 2>/dev/null | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
              if [[ "$remote_count" == "1" ]]; then
                push_remote="$("$git_bin" remote 2>/dev/null | /usr/bin/head -n 1)"
              else
                printf '✖ 当前分支没有上游，且无法唯一确定推送远程，已停止。\n'
                "$git_bin" remote -v
                return 1
              fi
            fi
          fi

          printf '\n▶ 正在创建不包含文件变更的空白 Commit...\n'
          if ! "$git_bin" commit --allow-empty -m 'chore: empty commit'; then
            printf '✖ 空白 Commit 创建失败，未执行 Push。\n'
            return 1
          fi
          commit_hash="$("$git_bin" rev-parse --short HEAD 2>/dev/null || true)"

          printf '\n▶ 正在推送空白 Commit...\n'
          if [[ -n "$upstream" ]]; then
            if ! "$git_bin" push; then
              printf '✖ Push 失败；空白 Commit 已保留在本地：%s\n' "$commit_hash"
              return 1
            fi
          else
            if ! "$git_bin" push -u "$push_remote" "$current_branch"; then
              printf '✖ Push 失败；空白 Commit 已保留在本地：%s\n' "$commit_hash"
              return 1
            fi
          fi

          printf '\n✔ 空白 Commit 已推送：%s\n' "$commit_hash"
        }
        git_empty_commit_push
        """#
    }

    func activateTerminalWhenAvailable() {
        for attempt in 1...20 {
            if let runningApplication = terminalRunningApplication() {
                let didActivate = runningApplication.activate(options: [.activateAllWindows])
                writeLog("terminal activate attempt=\(attempt), success=\(didActivate)")
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        writeLog("terminal activate skipped, running app not found")
    }
}
