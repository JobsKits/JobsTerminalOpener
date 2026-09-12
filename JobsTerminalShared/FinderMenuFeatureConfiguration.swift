//
//  FinderMenuFeatureConfiguration.swift
//  JobsTerminalShared
//
//  Created by Jobs on 2026年9月13日，星期日.
//

import Darwin
import Foundation

enum FinderMenuFeature: String, CaseIterable {
    case open
    case podInstall = "pod-install"
    case flutterPubGet = "flutter-pub-get"
    case codeGraphBootstrap = "codegraph-bootstrap"
    case gitEmptyCommitPush = "git-empty-commit-push"

    var configurationTitle: String {
        switch self {
        /// 对任意单个本地文件或文件夹提供终端入口
        case .open:
            return "用终端打开 —— 任意单个本地文件或文件夹"
        /// 仅对合法 CocoaPods iOS 工程提供依赖安装入口
        case .podInstall:
            return "在终端执行 pod install —— 含 Podfile 和 *.xcodeproj"
        /// 仅对合法 Flutter 工程提供依赖拉取入口
        case .flutterPubGet:
            return "在终端执行 flutter pub get —— 合法 Flutter 工程"
        /// 仅对普通文件夹提供 CodeGraph 安装或升级入口
        case .codeGraphBootstrap:
            return "安装/升级 CodeGraph 代码地图 —— 普通文件夹"
        /// 仅对普通文件夹提供 Git 空白提交并推送入口
        case .gitEmptyCommitPush:
            return "在终端创建空白 Commit 并 Push —— 普通文件夹，Git 状态由终端校验"
        }
    }
}

struct FinderMenuFeatureConfiguration {
    static let infoDictionaryKey = "JobsTerminalEnabledFeatures"
    private static let directoryName = "JobsTerminalOpener"
    private static let fileName = "EnabledFinderMenuFeatures.txt"

    static func enabledFeatures(fallbackBundle: Bundle) -> Set<FinderMenuFeature> {
        if let configurationFileURL,
           let configuredValue = try? String(contentsOf: configurationFileURL, encoding: .utf8) {
            return features(from: configuredValue)
        }

        guard let configuredValue = fallbackBundle.object(forInfoDictionaryKey: infoDictionaryKey) as? String else {
            return Set(FinderMenuFeature.allCases)
        };return features(from: configuredValue)
    }

    static func save(_ features: Set<FinderMenuFeature>) throws {
        guard let configurationFileURL else {
            throw NSError(
                domain: "com.jobs.JobsTerminalOpener.FeatureConfiguration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法确定当前用户目录。"]
            )
        }

        let directoryURL = configurationFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let configuredValue = FinderMenuFeature.allCases
            .filter { features.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
        try configuredValue.write(to: configurationFileURL, atomically: true, encoding: .utf8)
    }
}

private extension FinderMenuFeatureConfiguration {
    static var configurationFileURL: URL? {
        guard let passwordEntry = getpwuid(getuid()),
              let homeDirectoryPointer = passwordEntry.pointee.pw_dir else { return nil };return URL(fileURLWithPath: String(cString: homeDirectoryPointer), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func features(from configuredValue: String) -> Set<FinderMenuFeature> {
        let configuredIdentifiers = Set(
            configuredValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        );return Set(FinderMenuFeature.allCases.filter { configuredIdentifiers.contains($0.rawValue) })
    }
}
