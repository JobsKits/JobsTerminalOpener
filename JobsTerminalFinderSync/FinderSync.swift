//
//  FinderSync.swift
//  JobsTerminalFinderSync
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let dependencyProjectValidator = DependencyProjectValidator()
    private let logURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("JobsTerminalFinderSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("FinderSync.log")
    }()

    override init() {
        super.init()
        configureObservedDirectories()
        writeLog("FinderSync init, enabled features=\(enabledFeatures().map(\.rawValue).sorted().joined(separator: ","))")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let urls = candidateURLs()
        writeLog("menu kind=\(menuKind.rawValue), candidates=\(urls.map(\.path).joined(separator: " | "))")
        guard menuKind == .contextualMenuForItems, urls.count == 1 else { return nil }

        let enabledFeatures = enabledFeatures()
        let menu = NSMenu(title: "")
        if enabledFeatures.contains(.open) {
            let openItem = NSMenuItem(title: "用终端打开", action: #selector(openInTerminal(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.isEnabled = true
            menu.addItem(openItem)
        }

        let directoryURL = urls[0]
        if enabledFeatures.contains(.podInstall),
           dependencyProjectValidator.isCocoaPodsProject(at: directoryURL) {
            let podInstallItem = NSMenuItem(title: "在终端执行 pod install", action: #selector(runPodInstallInTerminal(_:)), keyEquivalent: "")
            podInstallItem.target = self
            podInstallItem.isEnabled = true
            menu.addItem(podInstallItem)
        }

        if enabledFeatures.contains(.flutterPubGet),
           dependencyProjectValidator.isFlutterProject(at: directoryURL) {
            let flutterPubGetItem = NSMenuItem(title: "在终端执行 flutter pub get", action: #selector(runFlutterPubGetInTerminal(_:)), keyEquivalent: "")
            flutterPubGetItem.target = self
            flutterPubGetItem.isEnabled = true
            menu.addItem(flutterPubGetItem)
        }

        if enabledFeatures.contains(.codeGraphBootstrap),
           dependencyProjectValidator.isCodeGraphTargetFolder(at: directoryURL) {
            let codeGraphItem = NSMenuItem(title: "安装/升级 CodeGraph 代码地图", action: #selector(installOrUpgradeCodeGraph(_:)), keyEquivalent: "")
            codeGraphItem.target = self
            codeGraphItem.isEnabled = true
            menu.addItem(codeGraphItem)
        }

        if enabledFeatures.contains(.gitEmptyCommitPush),
           dependencyProjectValidator.isGitEmptyCommitPushTargetFolder(at: directoryURL) {
            let gitEmptyCommitPushItem = NSMenuItem(title: "在终端创建空白 Commit 并 Push", action: #selector(pushEmptyCommitInTerminal(_:)), keyEquivalent: "")
            gitEmptyCommitPushItem.target = self
            gitEmptyCommitPushItem.isEnabled = true
            menu.addItem(gitEmptyCommitPushItem)
        };return menu.items.isEmpty ? nil : menu
    }
}

private extension FinderSync {
    func enabledFeatures() -> Set<FinderMenuFeature> {
        FinderMenuFeatureConfiguration.enabledFeatures(fallbackBundle: Bundle(for: FinderSync.self))
    }

    func configureObservedDirectories() {
        let directoryURLs: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        FIFinderSyncController.default().directoryURLs = directoryURLs
        writeLog("observed=\(directoryURLs.map(\.path).sorted().joined(separator: " | "))")
    }

    @objc func openInTerminal(_ sender: Any?) {
        performTerminalAction(.open)
    }

    @objc func runPodInstallInTerminal(_ sender: Any?) {
        performTerminalAction(.podInstall)
    }

    @objc func runFlutterPubGetInTerminal(_ sender: Any?) {
        performTerminalAction(.flutterPubGet)
    }

    @objc func installOrUpgradeCodeGraph(_ sender: Any?) {
        performTerminalAction(.codeGraphBootstrap)
    }

    @objc func pushEmptyCommitInTerminal(_ sender: Any?) {
        performTerminalAction(.gitEmptyCommitPush)
    }

    func performTerminalAction(_ action: TerminalAction) {
        let urls = candidateURLs()
        var messages: [String] = []
        writeLog("action=\(action.rawValue), candidates=\(urls.map(\.path).joined(separator: " | "))")

        for url in urls {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let requestURL = try terminalOpenRequestURL(fileURL: url, action: action)
                writeLog("request terminal open via \(requestURL.absoluteString)")
                guard NSWorkspace.shared.open(requestURL) else {
                    throw FinderSyncOpenError.requestFailed
                }
                writeLog("delegate terminal open request accepted \(url.path)")
                return
            } catch {
                writeLog("failed \(url.path): \(error.localizedDescription)")
                messages.append(error.localizedDescription)
            }
        }

        showFailureAlert(title: action.failureTitle, messages: messages)
    }

    func terminalOpenRequestURL(fileURL: URL, action: TerminalAction) throws -> URL {
        var components = URLComponents()
        components.scheme = "jobsterminalopener"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: fileURL.path),
            URLQueryItem(name: "action", value: action.rawValue)
        ]

        guard let requestURL = components.url else {
            throw FinderSyncOpenError.invalidRequestURL
        };return requestURL
    }

    func candidateURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        guard let selectedURLs = controller.selectedItemURLs(),
              selectedURLs.count == 1,
              let selectedURL = selectedURLs.first,
              selectedURL.isFileURL else { return [] };return [selectedURL.standardizedFileURL]
    }

    func showFailureAlert(title: String, messages: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = messages.isEmpty ? "请选择一个文件或文件夹后再试。" : messages.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func writeLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("JobsTerminalFinderSync %@", message)

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            return
        }

        try? Data(line.utf8).write(to: logURL)
    }
}

private enum TerminalAction: String {
    case open
    case podInstall = "pod-install"
    case flutterPubGet = "flutter-pub-get"
    case codeGraphBootstrap = "codegraph-bootstrap"
    case gitEmptyCommitPush = "git-empty-commit-push"

    var failureTitle: String {
        switch self {
        /// 普通打开终端请求失败
        case .open:
            return "用终端打开失败"
        /// 在目标文件夹执行 pod install 请求失败
        case .podInstall:
            return "执行 pod install 失败"
        /// 在目标文件夹执行 flutter pub get 请求失败
        case .flutterPubGet:
            return "执行 flutter pub get 失败"
        /// 为目标文件夹安装或升级 CodeGraph 请求失败
        case .codeGraphBootstrap:
            return "安装/升级 CodeGraph 失败"
        /// 在当前文件夹创建空白 Commit 并 Push 请求失败
        case .gitEmptyCommitPush:
            return "空白 Commit 并 Push 失败"
        }
    }
}

private enum FinderSyncOpenError: LocalizedError {
    case invalidRequestURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        /// 无法创建合法的宿主 App 请求地址
        case .invalidRequestURL:
            return "创建终端操作请求失败"
        /// 系统没有接受唤起宿主 App 的请求
        case .requestFailed:
            return "无法唤起 JobsTerminalOpener 宿主 App"
        }
    }
}
