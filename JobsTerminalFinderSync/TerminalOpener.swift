//
//  TerminalOpener.swift
//  JobsTerminalFinderSync
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit

struct TerminalOpener {
    private let writeLog: (String) -> Void

    init(writeLog: @escaping (String) -> Void = { _ in }) {
        self.writeLog = writeLog
    }

    func openTerminal(from fileURL: URL) throws -> URL {
        let standardizedURL = fileURL.standardizedFileURL
        guard standardizedURL.isFileURL else {
            throw TerminalOpenError.unsupportedURL(fileURL)
        }

        let directoryURL = terminalWorkingDirectory(from: standardizedURL)
        try runTerminalCommand(directoryURL: directoryURL)
        return directoryURL
    }
}

private extension TerminalOpener {
    enum TerminalOpenError: LocalizedError {
        case unsupportedURL(URL)
        case missingTerminal
        case terminalCommandFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedURL(let url):
                return "不是本地文件路径：\(url.absoluteString)"
            case .missingTerminal:
                return "没有找到系统 Terminal.app"
            case .terminalCommandFailed(let message):
                return message
            }
        }
    }

    func terminalWorkingDirectory(from fileURL: URL) -> URL {
        if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
           values.isDirectory == true,
           values.isPackage != true {
            return fileURL
        };return fileURL.deletingLastPathComponent()
    }

    func runTerminalCommand(directoryURL: URL) throws {
        let terminalURL = try terminalApplicationURL()

        writeLog("terminal target directory=\(directoryURL.path)")
        writeLog("terminal app=\(terminalURL.path)")
        try openDirectoryInTerminal(directoryURL)
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

    func openDirectoryInTerminal(_ directoryURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            terminalOpenAppleScript(),
            directoryURL.path
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw TerminalOpenError.terminalCommandFailed("请求 Terminal.app 执行 cd 失败：\(error.localizedDescription)")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        writeLog("terminal cd directory exit=\(process.terminationStatus), output=\(output)")
        guard process.terminationStatus == 0 else {
            throw TerminalOpenError.terminalCommandFailed("Terminal.app 执行 cd 失败：\(output)")
        }
    }

    func terminalOpenAppleScript() -> String {
        """
        on run argv
            set targetPath to item 1 of argv
            tell application "Terminal"
                activate
                do script "cd " & quoted form of targetPath
            end tell
        end run
        """
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
