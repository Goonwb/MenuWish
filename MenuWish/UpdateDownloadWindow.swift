import AppKit

@MainActor
final class UpdateDownloadWindow: NSWindowController, NSWindowDelegate {
    private let release: ReleaseDetails
    private let installer: ReleaseInstaller
    private let isEnglish: Bool
    private let onClose: () -> Void
    private let heading = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let primary = NSButton(title: "", target: nil, action: nil)
    private let cancel = NSButton(title: "", target: nil, action: nil)
    private var operation: Task<Void, Never>?
    private var downloadedFile: URL?
    private var isMounting = false
    private var isClosed = false
    private var isDownloading = false

    init(release: ReleaseDetails, installer: ReleaseInstaller, isEnglish: Bool, onClose: @escaping () -> Void) {
        self.release = release
        self.installer = installer
        self.isEnglish = isEnglish
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "MenuWish · " + release.version
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = window.contentView!
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 198, width: 412, height: 28)
        detail.frame = NSRect(x: 24, y: 109, width: 412, height: 76)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        progress.frame = NSRect(x: 24, y: 86, width: 412, height: 16)
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        cancel.frame = NSRect(x: 214, y: 22, width: 100, height: 32)
        cancel.bezelStyle = .rounded
        cancel.target = self
        cancel.action = #selector(cancelDownload)
        cancel.keyEquivalent = "\u{1b}"
        primary.frame = NSRect(x: 318, y: 22, width: 120, height: 32)
        primary.bezelStyle = .rounded
        primary.target = self
        primary.action = #selector(primaryAction)
        primary.keyEquivalent = "\r"
        for view in [heading, detail, progress, cancel, primary] { content.addSubview(view) }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func text(_ chinese: String, _ english: String) -> String { isEnglish ? english : chinese }

    func start() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        beginDownload()
    }

    private func beginDownload() {
        isDownloading = true
        window?.contentView?.viewWithTag(101)?.removeFromSuperview()
        heading.stringValue = text("正在下载更新", "Downloading Update")
        detail.stringValue = text("正在连接…", "Connecting…")
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        primary.isHidden = true
        cancel.title = text("取消", "Cancel")
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await UpdateDownload.download(installer) { [weak self] received, total in
                    Task { @MainActor [weak self] in
                        guard let self, !self.isClosed, self.isDownloading else { return }
                        self.progress.isIndeterminate = false
                        self.progress.doubleValue = Double(received) / Double(total)
                        let amount = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
                        let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                        self.detail.stringValue = received == total
                            ? self.text("正在校验…", "Verifying…")
                            : "\(amount) / \(size) · \(Int(Double(received) / Double(total) * 100))%"
                    }
                }
                guard !Task.isCancelled, !isClosed else { UpdateDownload.discard(file); return }
                isDownloading = false
                downloadedFile = file
                progress.stopAnimation(nil)
                progress.isIndeterminate = false
                progress.doubleValue = 1
                heading.stringValue = text("更新已准备好", "Update Ready")
                detail.stringValue = text("点击「退出并安装」打开安装窗口。",
                    "Choose Quit & Install to open the installer.")
                primary.title = text("退出并安装", "Quit & Install")
                primary.isHidden = false
                cancel.title = text("稍后", "Later")
            } catch {
                guard !Task.isCancelled, !isClosed else { return }
                showFailure(error, mounting: false)
            }
            operation = nil
        }
    }

    @objc private func primaryAction() {
        guard operation == nil else { return }
        guard let file = downloadedFile else { beginDownload(); return }
        isMounting = true
        primary.isEnabled = false
        cancel.isEnabled = false
        window?.standardWindowButton(.closeButton)?.isEnabled = false
        heading.stringValue = text("正在打开安装窗口", "Opening Installer")
        detail.stringValue = text("打开后将自动退出。", "MenuWish will quit once it opens.")
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let volume = try await UpdateDownload.mount(file, installer: installer)
                guard NSWorkspace.shared.open(volume) else { throw UpdateDownloadError.cannotMount }
                // Keep the mounted image and its backing file for the user's drag-to-install step.
                NSApp.terminate(nil)
            } catch {
                isMounting = false
                primary.isEnabled = true
                cancel.isEnabled = true
                window?.standardWindowButton(.closeButton)?.isEnabled = true
                showFailure(error, mounting: true)
            }
            operation = nil
        }
    }

    private func showFailure(_ error: Error, mounting: Bool) {
        isDownloading = false
        progress.stopAnimation(nil)
        progress.isIndeterminate = false
        progress.doubleValue = 0
        heading.stringValue = text(mounting ? "无法打开安装窗口" : "下载更新失败",
                                   mounting ? "Unable to Open Installer" : "Update Download Failed")
        if error is UpdateDownloadError {
            detail.stringValue = text("安装包校验或打开失败，请重新下载。",
                "Unable to verify or open the installer. Please download it again.")
        } else if let network = error as? URLError {
            detail.stringValue = network.code == .timedOut
                ? text("下载超时，请重试。", "Download timed out. Please retry.")
                : text("连接失败，请检查网络后重试。", "Connection failed. Check your network and retry.")
        } else {
            detail.stringValue = text("下载失败，请重试或前往发布页面。", "Download failed. Retry or visit the release page.")
        }
        if let file = downloadedFile { UpdateDownload.discard(file); downloadedFile = nil }
        primary.title = text("重新下载", "Retry")
        primary.isHidden = false
        cancel.title = text("关闭", "Close")
        // A secondary link remains available without leaving a failed download as the only option.
        if window?.contentView?.viewWithTag(101) == nil {
            let link = NSButton(title: text("发布页面", "Release Page"), target: self, action: #selector(openReleasePage))
            link.tag = 101
            link.isBordered = false
            link.contentTintColor = .linkColor
            link.frame = NSRect(x: 20, y: 22, width: 130, height: 32)
            window?.contentView?.addSubview(link)
        }
    }

    @objc private func openReleasePage() { NSWorkspace.shared.open(release.page) }
    @objc private func cancelDownload() { window?.performClose(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !isMounting }
    func windowWillClose(_ notification: Notification) {
        isClosed = true
        isDownloading = false
        operation?.cancel()
        if let file = downloadedFile { UpdateDownload.discard(file); downloadedFile = nil }
        onClose()
    }
}
