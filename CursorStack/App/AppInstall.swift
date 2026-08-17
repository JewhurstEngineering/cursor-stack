import AppKit

enum AppInstall {
    static var applicationsURL: URL {
        FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
            ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    static var installedAppURL: URL {
        applicationsURL.appendingPathComponent("CursorStack.app", isDirectory: true)
    }

    static var isRunningFromApplications: Bool {
        let applicationsPath = applicationsURL.standardizedFileURL.path + "/"
        return Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix(applicationsPath)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedAppURL.path)
    }

    @discardableResult
    static func copyRunningAppToApplications() throws -> URL {
        let source = Bundle.main.bundleURL.standardizedFileURL
        let destination = installedAppURL.standardizedFileURL
        guard source != destination else {
            registerWithLaunchServices(destination)
            return destination
        }

        let temporaryDestination = applicationsURL.appendingPathComponent(
            ".CursorStack-installing-\(UUID().uuidString).app",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDestination) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = [source.path, temporaryDestination.path]
        let errorPipe = Pipe()
        task.standardError = errorPipe
        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let output = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "CursorStack.AppInstall",
                code: Int(task.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: output?.isEmpty == false
                        ? output!
                        : "Copy to Applications failed (ditto \(task.terminationStatus)).",
                ]
            )
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryDestination, to: destination)
        registerWithLaunchServices(destination)
        return destination
    }

    /// Launch Services normally reuses the running bundle identifier. A
    /// detached `open -n` starts the installed copy after this one terminates.
    static func launchInstalledAndTerminate() {
        let escapedPath = installedAppURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [
            "-c",
            "((sleep 1.2; /usr/bin/open -n '\(escapedPath)') &)",
        ]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func registerWithLaunchServices(_ appURL: URL) {
        let launchServicesRegister =
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        _ = run("/usr/bin/xattr", ["-cr", appURL.path])
        _ = run(launchServicesRegister, ["-f", appURL.path])
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }
}
