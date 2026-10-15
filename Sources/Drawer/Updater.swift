import AppKit
import CryptoKit
import SwiftUI

/// Looks for a newer release on GitHub and, when asked, installs it: downloads the DMG, checks it against the published
/// checksum, swaps the app in place and relaunches. No third-party framework; the only network call is to api.github.com.
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let dmg: URL
        let checksum: URL?
        let page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state = State.idle
    private var lastAutoCheck: Date {
        get { UserDefaults.standard.object(forKey: "updateLastCheck") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "updateLastCheck") }
    }
    private var promptedVersion: String {
        get { UserDefaults.standard.string(forKey: "updatePromptedVersion") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "updatePromptedVersion") }
    }

    var available: Release? { if case .available(let r) = state { return r } else { return nil } }

    // MARK: Checking

    /// Called at launch and then every few hours: asks GitHub at most once a day, and only if the user allows it.
    func checkIfDue() {
        guard Settings.shared.v.checkForUpdates, !AppModel.shared.standby else { return }
        if Self.isTestRun { if ProcessInfo.processInfo.environment["DRAWER_UPDATE_FILE"] != nil { check(manual: true) }; return }
        if Date().timeIntervalSince(lastAutoCheck) > 24 * 3600 { check(manual: false) }
    }

    private static var isTestRun: Bool { ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("DRAWER_") } }

    func check(manual: Bool) {
        switch state { case .checking, .downloading, .installing: return; default: break }
        // Debug aid: DRAWER_UPDATE_FILE=/path/Drawer.dmg offers that file as version 99 (and DRAWER_UPDATE_INSTALL=1 installs it).
        if let file = ProcessInfo.processInfo.environment["DRAWER_UPDATE_FILE"] {
            state = .available(Release(version: "99", notes: "", dmg: URL(fileURLWithPath: file), checksum: nil, page: Brand.repoURL))
            if ProcessInfo.processInfo.environment["DRAWER_UPDATE_INSTALL"] != nil { install() }
            return
        }
        state = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/andikanbassey/Drawer/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(Brand.name)/\(Brand.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: State
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, let release = Self.parse(data) {
                result = Self.isNewer(release.version, than: Brand.version) ? .available(release) : .upToDate
            } else if manual {
                result = .failed(error?.localizedDescription ?? "Couldn't reach GitHub. Try again later.")
            } else {
                result = .idle
            }
            DispatchQueue.main.async {
                self.lastAutoCheck = Date()
                self.state = result
                if !manual, let r = self.available { self.announce(r) }
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        func asset(_ name: String) -> URL? {
            assets.first { $0["name"] as? String == name }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        }
        guard let dmg = asset("Drawer.dmg") else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, notes: json["body"] as? String ?? "", dmg: dmg, checksum: asset("Drawer.dmg.sha256"), page: page)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Asks once per version when the check ran by itself; the menu bar item and Settings stay as a reminder.
    private func announce(_ r: Release) {
        guard promptedVersion != r.version else { return }
        promptedVersion = r.version
        let alert = NSAlert()
        alert.messageText = "\(Brand.name) \(r.version) is available"
        alert.informativeText = "You have \(Brand.version). Drawer can download and install the update, then reopen."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { install() }
    }

    // MARK: Installing

    func install() {
        guard let release = available else { return }
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            // Not allowed to replace the app where it is (for example it sits in a protected folder): open the download page.
            NSWorkspace.shared.open(release.page)
            return
        }
        state = .downloading(0)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("drawer-update-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let dmg = try await self.download(release.dmg, to: work.appendingPathComponent("Drawer.dmg"))
                if let sum = release.checksum { try await self.verify(dmg, against: sum) }
                await MainActor.run { self.state = .installing }
                let staged = try self.stage(dmg, in: work)
                try self.relaunch(replacing: target, with: staged, work: work)
            } catch {
                try? FileManager.default.removeItem(at: work)
                await MainActor.run { self.state = .failed((error as? UpdateError)?.message ?? error.localizedDescription) }
            }
        }
    }

    private struct UpdateError: Error { let message: String }

    private func download(_ url: URL, to file: URL) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = response.expectedContentLength
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var buffer = Data(), received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 18 {
                try handle.write(contentsOf: buffer); received += Int64(buffer.count); buffer.removeAll(keepingCapacity: true)
                if total > 0 { let p = Double(received) / Double(total); await MainActor.run { self.state = .downloading(p) } }
            }
        }
        try handle.write(contentsOf: buffer)
        return file
    }

    private func verify(_ file: URL, against sumURL: URL) async throws {
        let (data, _) = try await URLSession.shared.data(from: sumURL)
        guard let expected = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).first?.lowercased() else {
            throw UpdateError(message: "The update's checksum file is empty.")
        }
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError(message: "The download didn't match its checksum, so it was not installed.") }
    }

    /// Mounts the DMG, copies the app out to a staging folder and checks that it really is Drawer and is intact.
    private func stage(_ dmg: URL, in work: URL) throws -> URL {
        let mount = work.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? Self.run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
        let staged = work.appendingPathComponent("Drawer.app")
        try Self.run("/usr/bin/ditto", [mount.appendingPathComponent("Drawer.app").path, staged.path])
        guard Bundle(url: staged)?.bundleIdentifier == Brand.bundleID else { throw UpdateError(message: "The download isn't \(Brand.name).") }
        try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        return staged
    }

    /// A small script waits for this process to quit, swaps the app and opens the new one. If the copy fails the old app is put back.
    private func relaunch(replacing target: URL, with staged: URL, work: URL) throws {
        let script = work.appendingPathComponent("swap.sh")
        try """
        #!/bin/sh
        PID="$1"; TARGET="$2"; STAGED="$3"; WORK="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        OLD="$TARGET.old"
        rm -rf "$OLD"
        if mv "$TARGET" "$OLD" && /usr/bin/ditto "$STAGED" "$TARGET"; then
            rm -rf "$OLD"
        else
            rm -rf "$TARGET"; mv "$OLD" "$TARGET"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        /usr/bin/open "$TARGET"
        rm -rf "$WORK"
        """.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, staged.path, work.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: tool); p.arguments = args; p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else { throw UpdateError(message: "The update couldn't be unpacked (\((tool as NSString).lastPathComponent)).") }
        return text
    }
}

/// The Updates row in Settings › General › About.
struct UpdateRow: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Row("Updates", subtitle: subtitle) {
            switch updater.state {
            case .available: Button("Update Now") { updater.install() }
            case .checking, .installing: ProgressView().controlSize(.small)
            case .downloading(let p): ProgressView(value: p).frame(width: 90)
            default: Button("Check for Updates") { updater.check(manual: true) }
            }
        }
    }

    private var subtitle: String {
        switch updater.state {
        case .idle: "Drawer \(Brand.version). Updates come from GitHub releases."
        case .checking: "Checking…"
        case .upToDate: "You're up to date (\(Brand.version))."
        case .available(let r): "\(Brand.name) \(r.version) is available. Drawer downloads it, checks it and reopens."
        case .downloading: "Downloading the update…"
        case .installing: "Installing. Drawer will reopen."
        case .failed(let m): m
        }
    }
}
