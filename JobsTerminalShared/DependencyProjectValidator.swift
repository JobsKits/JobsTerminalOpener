//
//  DependencyProjectValidator.swift
//  JobsTerminalShared
//
//  Created by Jobs on 2026年9月13日，星期日.
//

import Foundation

struct DependencyProjectValidator {
    private let fileManager = FileManager.default

    func isCocoaPodsProject(at directoryURL: URL) -> Bool {
        guard isOrdinaryDirectory(directoryURL),
              isRegularFile(directoryURL.appendingPathComponent("Podfile")),
              let childURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return false };return childURLs.contains { childURL in
            guard childURL.pathExtension.caseInsensitiveCompare("xcodeproj") == .orderedSame,
                  let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey]) else { return false };return values.isDirectory == true
        }
    }

    func isFlutterProject(at directoryURL: URL) -> Bool {
        guard isOrdinaryDirectory(directoryURL),
              isOrdinaryDirectory(directoryURL.appendingPathComponent("lib", isDirectory: true)) else { return false }

        let pubspecURL = directoryURL.appendingPathComponent("pubspec.yaml")
        guard isRegularFile(pubspecURL),
              let pubspec = try? String(contentsOf: pubspecURL, encoding: .utf8) else { return false }

        let flutterSDKPattern = #"(?m)^[ \t]+sdk:[ \t]*flutter[ \t]*(?:#.*)?$"#
        return pubspec.range(of: flutterSDKPattern, options: .regularExpression) != nil
    }

    func isCodeGraphTargetFolder(at directoryURL: URL) -> Bool {
        isOrdinaryDirectory(directoryURL)
    }

    func isGitEmptyCommitPushTargetFolder(at directoryURL: URL) -> Bool {
        isOrdinaryDirectory(directoryURL)
    }
}

private extension DependencyProjectValidator {
    func isOrdinaryDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false };return values.isDirectory == true && values.isPackage != true
    }

    func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else { return false };return values.isRegularFile == true
    }
}
