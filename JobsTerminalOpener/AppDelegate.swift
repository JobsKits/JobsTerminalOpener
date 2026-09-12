//
//  AppDelegate.swift
//  JobsTerminalOpener
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let extensionIdentifier = "com.jobs.JobsTerminalOpener.FinderSyncExtension"
    private let logURL = URL(fileURLWithPath: "/tmp/JobsTerminalOpener.log")
    private let finderRefreshMarkerURL = URL(fileURLWithPath: "/tmp/JobsTerminalOpenerNeedsFinderRestart")
    private let finderRefreshDelay: TimeInterval = 2.5
    private let finderRefreshRetryDelay: TimeInterval = 1.0
    private let finderRefreshRetryLimit = 12
    private lazy var terminalOpener = TerminalOpener { [weak self] message in
        self?.writeLog(message)
    }
    private var didHandleTerminalOpenRequest = false
    private var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        registerTerminalOpenURLHandler()
        writeLog("applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeLog("applicationDidFinishLaunching begin")
        if finishURLRequestLaunchIfNeeded() {
            writeLog("applicationDidFinishLaunching end")
            return
        }

        showMainWindow()
        scheduleFinderRefreshIfNeeded()
        writeLog("applicationDidFinishLaunching end")
    }

    func showMainWindow() {
        let viewController = MainViewController()
        _ = viewController.view
        writeLog("main view loaded")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jobs Terminal Opener"
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.center()
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        writeLog("application open urls=\(urls.map(\.absoluteString).joined(separator: " | "))")
        urls.forEach(handleTerminalOpenRequest)
    }
}

private extension AppDelegate {
    func registerTerminalOpenURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleTerminalOpenAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleTerminalOpenAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            writeLog("invalid terminal open AppleEvent")
            return
        }

        writeLog("application AppleEvent url=\(url.absoluteString)")
        handleTerminalOpenRequest(url)
    }

    func handleTerminalOpenRequest(_ url: URL) {
        guard url.scheme == "jobsterminalopener",
              url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else {
            writeLog("invalid terminal open url=\(url.absoluteString)")
            return
        }

        let actionValue = components.queryItems?.first(where: { $0.name == "action" })?.value ?? TerminalOpener.Action.open.rawValue
        guard let action = TerminalOpener.Action(rawValue: actionValue) else {
            writeLog("invalid terminal action=\(actionValue)")
            return
        }
        guard let feature = FinderMenuFeature(rawValue: actionValue),
              FinderMenuFeatureConfiguration.enabledFeatures(fallbackBundle: Bundle.main).contains(feature) else {
            writeLog("disabled terminal action=\(actionValue)")
            return
        }

        didHandleTerminalOpenRequest = true
        do {
            let fileURL = URL(fileURLWithPath: path)
            let directoryURL = try terminalOpener.openTerminal(from: fileURL, action: action)
            writeLog("terminal action=\(action.rawValue) from host \(directoryURL.path)")
        } catch {
            writeLog("terminal action=\(action.rawValue) from host failed path=\(path), error=\(error.localizedDescription)")
            showTerminalOpenFailure(error.localizedDescription, action: action)
        }
    }

    func finishURLRequestLaunchIfNeeded() -> Bool {
        guard didHandleTerminalOpenRequest else { return false }

        NSApp.setActivationPolicy(.accessory)
        scheduleFinderRefreshIfNeeded()
        writeLog("skip main window after terminal open request")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        };return true
    }

    func showTerminalOpenFailure(_ message: String, action: TerminalOpener.Action) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch action {
        /// 普通打开终端请求失败
        case .open:
            alert.messageText = "用终端打开失败"
        /// 在目标文件夹执行 pod install 请求失败
        case .podInstall:
            alert.messageText = "执行 pod install 失败"
        /// 在目标文件夹执行 flutter pub get 请求失败
        case .flutterPubGet:
            alert.messageText = "执行 flutter pub get 失败"
        /// 为目标文件夹安装或升级 CodeGraph 请求失败
        case .codeGraphBootstrap:
            alert.messageText = "安装/升级 CodeGraph 失败"
        /// 在当前文件夹创建空白 Commit 并 Push 请求失败
        case .gitEmptyCommitPush:
            alert.messageText = "空白 Commit 并 Push 失败"
        }
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func scheduleFinderRefreshIfNeeded() {
        guard FileManager.default.fileExists(atPath: finderRefreshMarkerURL.path) else {
            writeLog("finder refresh marker missing")
            return
        }

        writeLog("schedule Finder refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + finderRefreshDelay) { [weak self] in
            self?.refreshFinderAfterExtensionActivation(remainingAttempts: self?.finderRefreshRetryLimit ?? 0)
        }
    }

    func refreshFinderAfterExtensionActivation(remainingAttempts: Int) {
        guard FileManager.default.fileExists(atPath: finderRefreshMarkerURL.path) else {
            writeLog("finder refresh marker already consumed")
            return
        }

        _ = runPluginKit(arguments: ["-e", "use", "-i", extensionIdentifier])
        if isFinderExtensionEnabledByPluginKit() {
            writeLog("Finder extension enabled, restart Finder")
            restartFinder()
            try? FileManager.default.removeItem(at: finderRefreshMarkerURL)
            return
        }

        guard remainingAttempts > 0 else {
            writeLog("Finder extension still not enabled, keep marker")
            return
        }

        writeLog("Finder extension not enabled yet, retry remaining=\(remainingAttempts)")
        DispatchQueue.main.asyncAfter(deadline: .now() + finderRefreshRetryDelay) { [weak self] in
            self?.refreshFinderAfterExtensionActivation(remainingAttempts: remainingAttempts - 1)
        }
    }

    func isFinderExtensionEnabledByPluginKit() -> Bool {
        let result = runPluginKit(arguments: ["-m", "-p", "com.apple.FinderSync", "-A", "-v"])
        let matchedLine = result.output.components(separatedBy: .newlines).first { $0.contains(extensionIdentifier) } ?? ""
        let isEnabled = matchedLine.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        writeLog("Finder extension status line=\(matchedLine), isEnabled=\(isEnabled)")
        return isEnabled
    }

    func restartFinder() {
        let result = runCommand(executablePath: "/usr/bin/killall", arguments: ["Finder"])
        writeLog("killall Finder success=\(result.didSucceed), output=\(result.output)")
    }

    func runPluginKit(arguments: [String]) -> AppCommandResult {
        runCommand(executablePath: "/usr/bin/pluginkit", arguments: arguments)
    }

    func runCommand(executablePath: String, arguments: [String]) -> AppCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            writeLog("\(executablePath) \(arguments.joined(separator: " ")) failed: \(error.localizedDescription)")
            return AppCommandResult(didSucceed: false, output: error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        writeLog("\(executablePath) \(arguments.joined(separator: " ")) status=\(process.terminationStatus) output=\(output)")
        return AppCommandResult(didSucceed: process.terminationStatus == 0, output: output)
    }

    func writeLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("JobsTerminalOpener %@", message)

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

private struct AppCommandResult {
    let didSucceed: Bool
    let output: String
}
