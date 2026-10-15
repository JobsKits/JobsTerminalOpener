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
            gitEmptyCommitPushCommand(),
            codeGraphHomebrewCommand()
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
            set codeGraphHomebrewCommand to item 4 of argv
            set terminalCommand to "cd " & quoted form of targetPath
            if terminalAction is "pod-install" then
                set terminalCommand to terminalCommand & " && pod install"
            else if terminalAction is "flutter-pub-get" then
                set terminalCommand to terminalCommand & " && flutter pub get"
            else if terminalAction is "codegraph-bootstrap" then
                set codeGraphCommand to codeGraphHomebrewCommand & "\ncodegraph_find_brew() { jobs_brew_find; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_install_homebrew() { jobs_brew_install_or_exit; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_ensure_brew() { CODEGRAPH_BREW_BIN=$(codegraph_find_brew 2>/dev/null || true); if [ x${CODEGRAPH_BREW_BIN:-} = x ]; then printf '\n▶ 未检测到可用的 Homebrew，开始向上检查系统安装条件...\n'; codegraph_install_homebrew || return 1; CODEGRAPH_BREW_BIN=$(codegraph_find_brew 2>/dev/null || true); fi; if [ x${CODEGRAPH_BREW_BIN:-} = x ]; then printf '\n✖ Homebrew 安装后仍不可用。\n'; return 1; fi; CODEGRAPH_BREW_PREFIX=$(${CODEGRAPH_BREW_BIN} --prefix 2>/dev/null) || { printf '\n✖ 无法读取 Homebrew 安装目录。\n'; return 1; }; export PATH=${CODEGRAPH_BREW_PREFIX}/bin:${CODEGRAPH_BREW_PREFIX}/sbin:${PATH}; rehash 2>/dev/null || true; printf '\n✔ Homebrew 可用：'; ${CODEGRAPH_BREW_BIN} --version | head -n 1; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_has_npm() { command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_ensure_npm() { if codegraph_has_npm; then printf '\n✔ Node.js 可用：'; node --version; printf '✔ npm 可用：'; npm --version; return 0; fi; printf '\n▶ npm 或 Node.js 不存在或不可用，继续向上检查 Homebrew...\n'; codegraph_ensure_brew || return 1; if codegraph_has_npm; then printf '✔ 加载 Homebrew 环境后 Node.js 可用：'; node --version; printf '✔ npm 可用：'; npm --version; return 0; fi; if ${CODEGRAPH_BREW_BIN} list --formula node >/dev/null 2>&1; then printf '\n▶ Homebrew 已登记 Node.js，但 npm 仍不可用，正在重新安装 Node.js...\n'; ${CODEGRAPH_BREW_BIN} reinstall node || return 1; else printf '\n▶ 正在通过 Homebrew 安装 Node.js（包含 npm）...\n'; ${CODEGRAPH_BREW_BIN} install node || return 1; fi; CODEGRAPH_BREW_PREFIX=$(${CODEGRAPH_BREW_BIN} --prefix 2>/dev/null) || return 1; export PATH=${CODEGRAPH_BREW_PREFIX}/bin:${CODEGRAPH_BREW_PREFIX}/sbin:${PATH}; rehash 2>/dev/null || true; if ! codegraph_has_npm; then printf '\n✖ Node.js 安装或修复后，node/npm 仍不可用。\n'; return 1; fi; printf '\n✔ Node.js 已就绪：'; node --version; printf '✔ npm 已就绪：'; npm --version; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_ensure_cli() { if command -v codegraph >/dev/null 2>&1 && codegraph --version >/dev/null 2>&1; then printf '\n✔ CodeGraph 可用，当前版本：'; codegraph --version; printf '▶ 正在尝试升级 CodeGraph...\n'; if codegraph upgrade; then printf '\n✔ CodeGraph 升级检查完成。\n'; else printf '\n⚠ CodeGraph 升级失败，将使用当前可用版本继续建立代码地图。\n'; fi; return 0; fi; printf '\n▶ CodeGraph 不存在或不可用，正在通过 npm 安装最新版...\n'; npm install -g @colbymchenry/codegraph@latest || return 1; CODEGRAPH_NPM_PREFIX=$(npm prefix -g 2>/dev/null) || { printf '\n✖ 无法读取 npm 全局安装目录。\n'; return 1; }; export PATH=${CODEGRAPH_NPM_PREFIX}/bin:${PATH}; rehash 2>/dev/null || true; if ! command -v codegraph >/dev/null 2>&1 || ! codegraph --version >/dev/null 2>&1; then printf '\n✖ CodeGraph 安装后仍不可用。\n'; return 1; fi; printf '\n✔ CodeGraph 已就绪：'; codegraph --version; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_prepare_project() { if [ -d .codegraph ]; then printf '\n▶ 已存在项目代码地图，执行增量同步...\n'; codegraph sync . || return 1; else printf '\n▶ 正在为当前文件夹创建代码地图...\n'; codegraph init --yes . || return 1; fi; printf '\n✔ 当前项目 CodeGraph 状态：\n'; codegraph status .; }; "
                set codeGraphCommand to codeGraphCommand & "codegraph_ensure_npm && codegraph_ensure_cli && codegraph_prepare_project"
                set terminalCommand to terminalCommand & " && /bin/zsh -c " & quoted form of codeGraphCommand
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

    // 为 Terminal 的交互命令提供 Homebrew 安装路径选择。
    func codeGraphHomebrewCommand() -> String {
        #"""
        # >>> Jobs Homebrew install choice >>>
        # 输出安装诊断，避免混入返回的命令路径。
        jobs_brew_note() {
          print -u2 -r -- "ℹ $*"
        }
        # 验证候选能够执行；共享安装只读不代表未安装。
        jobs_brew_candidate_ok() {
          local candidate="$1" prefix
          [[ -n "$candidate" && -x "$candidate" ]] || return 1
          HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
          prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
          [[ "$prefix" == /* && -d "$prefix" ]]
        }
        # 发现既有健康安装，不以目录可写性决定是否重新安装。
        jobs_brew_find() {
          local candidate
          local -a candidates
          candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
            "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
          for candidate in "${candidates[@]}"; do
            if jobs_brew_candidate_ok "$candidate"; then
              print -r -- "$candidate"
              return 0
            fi
          done
          return 1
        }
        # 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
        jobs_brew_system_prefix() {
          case "$(/usr/bin/uname -m)" in
            arm64) print -r -- /opt/homebrew ;;
            *) print -r -- /usr/local ;;
          esac
        }
        # 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
        jobs_brew_choose_installation() {
          local answer="" system_prefix="$(jobs_brew_system_prefix)"
          if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
            jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
            return 1
          fi
          print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
          print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
          print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
          print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
          print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
          print -u2 -n -r -- "➤ 安装路径选择："
          if ! IFS= read -r answer; then
            jobs_brew_note "输入已取消或结束，停止安装。"
            return 1
          fi
          if [[ "$answer" == YES ]]; then
            typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
          else
            typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
          fi
        }
        # 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
        jobs_brew_install_system() {
          local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
          command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
          installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
          if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
            /bin/bash "$installer" || installer_result=$?
          else
            installer_result=1
          fi
          rm -- "$installer"
          if (( installer_result != 0 )); then
            jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
            return 1
          fi
          typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
          jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
        }
        # 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
        jobs_brew_install_user() {
          local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
          [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
            jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
            return 1
          }
          if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
            jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
            return 1
          fi
          git_bin="$(command -v git 2>/dev/null)"
          [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
          command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
          export HOMEBREW_NO_SUDO=1
          mkdir -p "${prefix:h}" || return 1
          stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
          if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
            rm -r -- "$stage"
            jobs_brew_note "获取官方稳定版本失败，停止安装。"
            return 1
          fi
          release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
          if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
             ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
             ! "$git_bin" -C "$stage/brew" checkout -b stable ||
             ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
             ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
            rm -r -- "$stage"
            jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
            return 1
          fi
          # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
          if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
            rm -r -- "$stage"
            return 1
          fi
          if ! mv "$stage/brew" "$prefix"; then
            rm -r -- "$stage"
            return 1
          fi
          rm -r -- "$stage"
          typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
          jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
        }
        # 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
        jobs_brew_save_shellenv() {
          local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
          [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
          shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
          profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
          if [[ -e "$profile_file" || -L "$profile_file" ]]; then
            awk '
              $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
              inside {
                block = block $0 ORS
                if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
                next
              }
              { print }
              END { if (inside) printf "%s", block }
            ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
          fi
          {
            print -r -- '# >>> Jobs Homebrew shellenv >>>'
            print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
          } >> "$profile_stage"
          if ! cmp -s "$profile_stage" "$profile_file"; then
            cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
          fi
          rm -- "$profile_stage"
        }
        # 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
        jobs_brew_activate() {
          local brew_env
          brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
          eval "$brew_env" || return 1
          typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
          export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
          rehash
          HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
          if [[ "${1:-}" == installed ]]; then
            if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
              export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
            fi
            jobs_brew_save_shellenv || return 1
          fi
        }
        # 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
        jobs_brew_install_or_exit() {
          local installed=""
          if [[ "${DRY_RUN:-0}" == 1 ]]; then
            jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
            return 0
          fi
          if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
            jobs_brew_choose_installation || exit 1
            case "$JOBS_HOMEBREW_INSTALL_MODE" in
              system) jobs_brew_install_system || exit 1 ;;
              user) jobs_brew_install_user || exit 1 ;;
              *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
            esac
            installed=installed
          fi
          jobs_brew_activate "$installed" || exit 1
        }
        # <<< Jobs Homebrew install choice <<<
        """#
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
