//
//  MainViewController.swift
//  JobsTerminalOpener
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit
import FinderSync

final class MainViewController: NSViewController {
    private let extensionIdentifier = "com.jobs.JobsTerminalOpener.FinderSyncExtension"
    private let extensionBundleName = "JobsTerminalFinderSync.appex"
    private let activationRetryDelay: TimeInterval = 1.0
    private let activationRetryLimit = 8
    private let logURL = URL(fileURLWithPath: "/tmp/JobsTerminalOpener.log")
    private let statusLabel = NSTextField(labelWithString: "")
    private let selectionStatusLabel = NSTextField(labelWithString: "")
    private var activationWorkItem: DispatchWorkItem?
    private var lastLaidOutViewSize: NSSize?
    private var lastLaidOutViewportSize: NSSize?
    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        return scrollView
    }()
    private lazy var scrollDocumentView = FlippedDocumentView(frame: .zero)
    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Finder 右键功能")
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .labelColor
        return label
    }()
    private lazy var detailLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "这里管理 JobsTerminalOpener 内的 5 项功能；另外 3 个独立扩展仍由总安装器选择。勾选后点击“保存功能选择”。")
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabelColor
        return label
    }()
    private lazy var selectionTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "可选功能")
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .labelColor
        return label
    }()
    private lazy var openFeatureCheckbox = makeFeatureCheckbox(for: .open)
    private lazy var podInstallFeatureCheckbox = makeFeatureCheckbox(for: .podInstall)
    private lazy var flutterPubGetFeatureCheckbox = makeFeatureCheckbox(for: .flutterPubGet)
    private lazy var codeGraphFeatureCheckbox = makeFeatureCheckbox(for: .codeGraphBootstrap)
    private lazy var gitEmptyCommitPushFeatureCheckbox = makeFeatureCheckbox(for: .gitEmptyCommitPush)
    private lazy var saveSelectionButton: NSButton = {
        let button = NSButton(title: "保存功能选择", target: self, action: #selector(saveFeatureSelectionAction))
        button.bezelStyle = .rounded
        return button
    }()
    private lazy var selectAllButton: NSButton = {
        let button = NSButton(title: "全部选择", target: self, action: #selector(selectAllFeaturesAction))
        button.bezelStyle = .rounded
        return button
    }()
    private lazy var deselectAllButton: NSButton = {
        let button = NSButton(title: "全部取消", target: self, action: #selector(deselectAllFeaturesAction))
        button.bezelStyle = .rounded
        return button
    }()
    private lazy var openSettingsButton: NSButton = {
        let button = NSButton(title: "打开扩展设置", target: self, action: #selector(openExtensionSettings))
        button.bezelStyle = .rounded
        return button
    }()
    private lazy var enableButton: NSButton = {
        let button = NSButton(title: "重新启用扩展", target: self, action: #selector(enableExtensionAction))
        button.bezelStyle = .rounded
        return button
    }()
    private lazy var refreshButton: NSButton = {
        let button = NSButton(title: "刷新状态", target: self, action: #selector(refreshStatusAction))
        button.bezelStyle = .rounded
        return button
    }()
    private lazy var tipLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "保存后关闭当前右键菜单并重新右键即可生效。如果扩展状态异常，再点击“重新启用扩展”。系统设置路径：隐私与安全性 -> 扩展 -> Finder 扩展。")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        return label
    }()
    private lazy var featureStackView: NSStackView = {
        let stackView = NSStackView(views: featureCheckboxes.map { $0.checkbox })
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        return stackView
    }()
    private lazy var selectionButtonStackView: NSStackView = {
        let stackView = NSStackView(views: [saveSelectionButton, selectAllButton, deselectAllButton])
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 12
        return stackView
    }()
    private lazy var extensionButtonStackView: NSStackView = {
        let stackView = NSStackView(views: [openSettingsButton, enableButton, refreshButton])
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 12
        return stackView
    }()
    private lazy var rootStackView: NSStackView = {
        let stackView = NSStackView(views: [
            titleLabel,
            detailLabel,
            selectionTitleLabel,
            featureStackView,
            selectionStatusLabel,
            selectionButtonStackView,
            statusLabel,
            extensionButtonStackView,
            tipLabel
        ])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.setCustomSpacing(18, after: detailLabel)
        stackView.setCustomSpacing(18, after: selectionButtonStackView)
        return stackView
    }()
    private var featureCheckboxes: [(feature: FinderMenuFeature, checkbox: NSButton)] {
        [
            (.open, openFeatureCheckbox),
            (.podInstall, podInstallFeatureCheckbox),
            (.flutterPubGet, flutterPubGetFeatureCheckbox),
            (.codeGraphBootstrap, codeGraphFeatureCheckbox),
            (.gitEmptyCommitPush, gitEmptyCommitPushFeatureCheckbox)
        ]
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 580))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        reloadFeatureSelection()
        enableFinderExtension()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let viewSize = view.bounds.size
        let viewportSize = scrollView.contentSize
        guard viewSize != lastLaidOutViewSize || viewportSize != lastLaidOutViewportSize else { return }
        lastLaidOutViewSize = viewSize
        lastLaidOutViewportSize = viewportSize
        layoutInterface()
    }
}

private extension MainViewController {
    func buildInterface() {
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        selectionStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        selectionStatusLabel.textColor = .secondaryLabelColor
        scrollView.documentView = scrollDocumentView
        scrollDocumentView.addSubview(rootStackView)
        view.addSubview(scrollView)
        layoutInterface()
    }

    func layoutInterface() {
        let horizontalMargin: CGFloat = 44
        let verticalMargin: CGFloat = 32
        scrollView.frame = view.bounds
        let viewportSize = scrollView.contentSize
        let contentWidth = max(viewportSize.width - horizontalMargin * 2, 0)
        if detailLabel.preferredMaxLayoutWidth != contentWidth {
            detailLabel.preferredMaxLayoutWidth = contentWidth
        }
        if tipLabel.preferredMaxLayoutWidth != contentWidth {
            tipLabel.preferredMaxLayoutWidth = contentWidth
        }
        rootStackView.frame.size.width = contentWidth
        let contentHeight = rootStackView.fittingSize.height
        scrollDocumentView.frame = NSRect(
            x: 0,
            y: 0,
            width: viewportSize.width,
            height: max(contentHeight + verticalMargin * 2, viewportSize.height)
        )
        rootStackView.frame = NSRect(
            x: horizontalMargin,
            y: verticalMargin,
            width: contentWidth,
            height: contentHeight
        )
    }

    func makeFeatureCheckbox(for feature: FinderMenuFeature) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: feature.configurationTitle, target: self, action: #selector(featureSelectionChanged))
        checkbox.allowsMixedState = false
        return checkbox
    }

    @objc func featureSelectionChanged() {
        updateSelectionStatus(prefix: "待保存")
    }

    func reloadFeatureSelection() {
        let enabledFeatures = FinderMenuFeatureConfiguration.enabledFeatures(fallbackBundle: Bundle.main)
        featureCheckboxes.forEach { selection in
            selection.checkbox.state = enabledFeatures.contains(selection.feature) ? .on : .off
        }
        updateSelectionStatus(prefix: "当前生效")
    }

    func selectedFeatures() -> Set<FinderMenuFeature> {
        Set(featureCheckboxes.compactMap { selection in
            selection.checkbox.state == .on ? selection.feature : nil
        })
    }

    func updateSelectionStatus(prefix: String) {
        let enabledCount = selectedFeatures().count
        selectionStatusLabel.stringValue = "\(prefix)：\(enabledCount)/\(FinderMenuFeature.allCases.count) 项。"
    }

    func setAllFeaturesEnabled(_ isEnabled: Bool) {
        featureCheckboxes.forEach { $0.checkbox.state = isEnabled ? .on : .off }
        updateSelectionStatus(prefix: "待保存")
    }

    @objc func saveFeatureSelectionAction() {
        let features = selectedFeatures()
        do {
            try FinderMenuFeatureConfiguration.save(features)
            updateSelectionStatus(prefix: "已保存")
            writeLog("saved enabled features=\(features.map(\.rawValue).sorted().joined(separator: ","))")
        } catch {
            selectionStatusLabel.stringValue = "保存失败：\(error.localizedDescription)"
            writeLog("save enabled features failed: \(error.localizedDescription)")
        }
    }

    @objc func selectAllFeaturesAction() {
        setAllFeaturesEnabled(true)
    }

    @objc func deselectAllFeaturesAction() {
        setAllFeaturesEnabled(false)
    }

    @objc func openExtensionSettings() {
        if #available(macOS 10.14, *) {
            FIFinderSyncController.showExtensionManagementInterface()
        } else if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.extensions") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    @objc func refreshStatusAction() {
        refreshStatus()
    }

    @objc func enableExtensionAction() {
        enableFinderExtension()
    }

    func enableFinderExtension() {
        activationWorkItem?.cancel()
        writeLog("enableFinderExtension begin")
        let didActivate = activateBundledFinderExtension()
        refreshStatus()

        if !didActivate || !isFinderExtensionEnabledByPluginKit() {
            scheduleActivationRetry(remainingAttempts: activationRetryLimit)
        }
    }

    func activateBundledFinderExtension() -> Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else {
            statusLabel.stringValue = "当前状态：没有找到 App 内置扩展目录。"
            return false
        }

        let extensionURL = plugInsURL.appendingPathComponent(extensionBundleName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: extensionURL.path) else {
            statusLabel.stringValue = "当前状态：没有找到内置 Finder 扩展。"
            writeLog("extension missing: \(extensionURL.path)")
            return false
        }

        let registerResult = runPluginKit(arguments: ["-a", extensionURL.path])
        let enableResult = runPluginKit(arguments: ["-e", "use", "-i", extensionIdentifier])
        let isEnabled = isFinderExtensionEnabledByPluginKit()
        writeLog("activate result register=\(registerResult.didSucceed), enable=\(enableResult.didSucceed), isEnabled=\(isEnabled)")
        return registerResult.didSucceed && enableResult.didSucceed && isEnabled
    }

    func scheduleActivationRetry(remainingAttempts: Int) {
        guard remainingAttempts > 0 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let didActivate = self.activateBundledFinderExtension()
            self.refreshStatus()
            guard !didActivate || !self.isFinderExtensionEnabledByPluginKit() else { return }
            self.scheduleActivationRetry(remainingAttempts: remainingAttempts - 1)
        }
        activationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + activationRetryDelay, execute: workItem)
    }

    func runPluginKit(arguments: [String]) -> PluginKitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            writeLog("pluginkit \(arguments.joined(separator: " ")) failed: \(error.localizedDescription)")
            return PluginKitResult(didSucceed: false, output: error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        writeLog("pluginkit \(arguments.joined(separator: " ")) status=\(process.terminationStatus) output=\(output)")
        return PluginKitResult(didSucceed: process.terminationStatus == 0, output: output)
    }

    func refreshStatus() {
        statusLabel.stringValue = isFinderExtensionEnabledByPluginKit() ? "当前状态：Finder 扩展已启用。" : "当前状态：Finder 扩展尚未启用。"
    }

    func isFinderExtensionEnabledByPluginKit() -> Bool {
        let result = runPluginKit(arguments: ["-m", "-p", "com.apple.FinderSync", "-A", "-v"])
        let lines = result.output.components(separatedBy: .newlines)
        let matchedLine = lines.first { $0.contains(extensionIdentifier) } ?? ""
        let isEnabled = matchedLine.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        writeLog("status line=\(matchedLine), isEnabled=\(isEnabled)")
        return isEnabled
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

private struct PluginKitResult {
    let didSucceed: Bool
    let output: String
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
