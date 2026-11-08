import AppKit

struct GitHubRelease: Decodable {
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
}

struct UpdateFailure: Error {
    let title: String
    let message: String
    let detail: String

    static func network(_ error: Error) -> Self {
        let error = error as NSError
        let detail = "Error domain: \(error.domain)\nError code: \(error.code)\nOriginal error: \(error.localizedDescription)"
        guard error.domain == NSURLErrorDomain else {
            return Self(title:"Update check incomplete",message:"Check again, or visit GitHub Releases.",detail:detail)
        }
        let text: (String,String)
        switch URLError.Code(rawValue:error.code) {
        case .notConnectedToInternet:
            text = ("No internet connection","Connect to the internet and check again.")
        case .timedOut:
            text = ("GitHub update check timed out","The check did not finish in time. Retry or view the releases page.")
        case .networkConnectionLost:
            text = ("Update download interrupted","This check did not finish. Try again.")
        case .cannotFindHost, .dnsLookupFailed:
            text = ("Update server not found","Unable to resolve GitHub's address. Check your network or proxy settings.")
        case .cannotConnectToHost:
            text = ("Unable to connect to GitHub","Unable to connect to the update service. Retry or open the releases page in your browser.")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            text = ("Unable to establish a secure connection","The update server's secure connection could not be verified.")
        case .cannotDecodeRawData, .cannotDecodeContentData, .cannotParseResponse, .badServerResponse:
            text = ("Unable to read update information","Release information is incomplete or incorrectly formatted.")
        default:
            text = ("Update check incomplete","Check again, or visit GitHub Releases.")
        }
        return Self(title:text.0,message:text.1,detail:detail)
    }
    static func http(_ response: HTTPURLResponse) -> Self {
        let code = response.statusCode
        let retry = response.value(forHTTPHeaderField:"Retry-After")
        let remaining = response.value(forHTTPHeaderField:"X-RateLimit-Remaining")
        let reset = response.value(forHTTPHeaderField:"X-RateLimit-Reset")
        var detail = "HTTP status: \(code)"
        for key in ["Retry-After","X-RateLimit-Remaining","X-RateLimit-Reset","X-GitHub-Request-Id"] {
            if let value = response.value(forHTTPHeaderField:key) {detail += "\n\(key): \(value)"}
        }
        if code == 429 || (code == 403 && (remaining == "0" || retry != nil)) {
            var resume: Date?
            if let retry {
                if let seconds = Double(retry), seconds.isFinite, seconds >= 0 {
                    resume = Date().addingTimeInterval(seconds)
                } else {
                    let format = DateFormatter(); format.locale = Locale(identifier:"en_US_POSIX")
                    format.timeZone = TimeZone(secondsFromGMT:0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    resume = format.date(from:retry)
                }
            }
            if resume == nil, remaining == "0", let reset, let seconds = Double(reset), seconds.isFinite {
                resume = Date(timeIntervalSince1970:seconds)
            }
            let message = resume.map {"Wait until " + DateFormatter.localizedString(from:$0,dateStyle:.short,timeStyle:.medium) + " before checking again."} ?? "Check again later."
            return Self(title:"Update check rate limit reached",message:message,detail:detail)
        }
        switch code {
        case 401,403: return Self(title:"Update request rejected",message:"GitHub rejected this request. Try again later.",detail:detail)
        case 404: return Self(title:"No stable release found",message:"Open GitHub Releases to view available versions.",detail:detail)
        case 407: return Self(title:"Proxy authentication required",message:"Complete proxy authentication, then check again.",detail:detail)
        case 500...599: return Self(title:"Update service error",message:"Try again later, or view GitHub Releases directly.",detail:detail)
        default: return Self(title:"Update check incomplete",message:"Check again, or visit GitHub Releases.",detail:detail)
        }
    }
    static func unreadable(_ detail: String) -> Self {
        Self(title:"Unable to read update information",message:"Release information is incomplete or incorrectly formatted.",detail:detail)
    }
}

/// All observable state is owned by the main queue. Network decoding runs off-main.
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()
    static let didChange = Notification.Name("BailongUpdateCheckChanged")
    static let repository = URL(string:"https://github.com/ruyeli/bailong-desktop-pet-english")!
    static let releases = repository.appendingPathComponent("releases")
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var generation = 0
    private var automatic = false
    private var slowTimer: Timer?
    private(set) var slow = false
    private(set) var failure: UpdateFailure?
    private(set) var checking = false
    private(set) var release: GitHubRelease?
    private(set) var releaseURL: URL?
    private(set) var status: String
    var headline: String {checking && slow ? "GitHub is responding slowly" : status}
    var explanation: String {
        if checking && slow {return "Still waiting for update information. You can keep waiting or cancel the check."}
        return failure?.message ?? ""
    }
    var recordText: String {failure == nil ? status : "Check incomplete · " + status}
    var technicalDetails: String {
        guard let failure else {return ""}
        return "Current version: \(Paths.version)\nEndpoint: https://api.github.com/repos/ruyeli/bailong-desktop-pet-english/releases/latest\nChecked: \(lastCheckText)\n\(failure.detail)"
    }
    var lastCheck: Date? {UserDefaults.standard.object(forKey:"englishUpdateLastCheck") as? Date}
    var lastCheckText: String {
        guard let date = lastCheck else {return "Not checked yet"}
        return DateFormatter.localizedString(from:date,dateStyle:.medium,timeStyle:.medium)
    }
    override private init() {
        status = UserDefaults.standard.string(forKey:"englishUpdateLastResult") ?? "Not checked yet"
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(preferencesChanged),name:PetPreferences.didChange,object:nil)
    }
    @objc private func preferencesChanged() {
        if automatic && checking && !PetPreferences.shared.bool("automaticallyCheckUpdates") {cancel()}
    }
    private func notify() {NotificationCenter.default.post(name:Self.didChange,object:self)}
    func check(automatically: Bool = false) {
        if checking {
            // A manual request adopts the in-flight startup check without issuing a second request.
            if !automatically {automatic = false; notify()}
            return
        }
        generation += 1; let requestGeneration = generation
        automatic = automatically; checking = true; release = nil; releaseURL = nil
        failure = nil; slow = false
        status = "Checking for updates…"; notify()
        let timer = Timer(timeInterval:8,repeats:false) { [weak self] _ in
            guard let self, self.checking, self.generation == requestGeneration else {return}
            self.slow = true; self.slowTimer = nil; self.notify()
        }
        slowTimer = timer; RunLoop.main.add(timer,forMode:.common)
        // Leave proxy settings untouched: URLSession uses macOS system proxies, and TUN uses system routing.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration:configuration); self.session = session
        var request = URLRequest(url:URL(string:"https://api.github.com/repos/ruyeli/bailong-desktop-pet-english/releases/latest")!)
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("2026-03-10",forHTTPHeaderField:"X-GitHub-Api-Version")
        request.setValue("BailongPet/"+Paths.version,forHTTPHeaderField:"User-Agent")
        task = session.dataTask(with:request) { [weak self] data,response,error in
            let result: Result<GitHubRelease,Error> = Result {
                if let error {throw error}
                guard let response = response as? HTTPURLResponse else {throw UpdateFailure.unreadable("No HTTP response received.")}
                guard response.statusCode == 200 else {throw UpdateFailure.http(response)}
                guard let data, !data.isEmpty else {throw UpdateFailure.unreadable("HTTP 200, empty response body.")}
                let release: GitHubRelease
                do {release = try JSONDecoder().decode(GitHubRelease.self,from:data)}
                catch {throw UpdateFailure.unreadable("HTTP 200, JSON parsing failed: \(error.localizedDescription)")}
                guard !release.draft, !release.prerelease else {throw UpdateFailure(title:"No stable version received",message:"This app checks stable releases only. View other versions on GitHub.",detail:"Release tag: \(release.tag_name)\ndraft: \(release.draft), prerelease: \(release.prerelease)")}
                guard let version = SemanticVersion.releaseTag(release.tag_name), version.prerelease.isEmpty else {
                    throw UpdateFailure(title:"Unrecognized release version",message:"View the release notes on GitHub Releases.",detail:"Release tag: \(release.tag_name)")
                }
                return release
            }
            DispatchQueue.main.async {
                guard let self, self.generation == requestGeneration else {return}
                self.complete(result)
            }
        }
        task?.resume()
    }
    private func complete(_ result: Result<GitHubRelease,Error>) {
        checking = false; slow = false; slowTimer?.invalidate(); slowTimer = nil
        task = nil; session?.finishTasksAndInvalidate(); session = nil
        if case .failure(let error) = result, (error as NSError).domain == NSURLErrorDomain,
           (error as NSError).code == URLError.cancelled.rawValue {
            automatic = false; status = "Update check canceled"; notify(); return
        }
        var newer = false
        switch result {
        case .success(let release):
            self.release = release
            releaseURL = Self.repository.appendingPathComponent("releases/tag").appendingPathComponent(release.tag_name)
            if let local = SemanticVersion(Paths.version), let remote = SemanticVersion.releaseTag(release.tag_name) {
                newer = local < remote
                status = newer ? "New version available: \(release.tag_name)" : local == remote ? "You're on the latest stable version" : "Local version is newer than the latest stable release"
            } else {
                failure = UpdateFailure(title:"Unable to compare versions",message:"This app's version number is invalid. Check the releases page manually.",detail:"Current version: \(Paths.version)")
                self.release = nil
                status = failure!.title
            }
        case .failure(let error):
            failure = (error as? UpdateFailure) ?? UpdateFailure.network(error)
            status = failure!.title
        }
        UserDefaults.standard.set(Date(),forKey:"englishUpdateLastCheck")
        UserDefaults.standard.set(recordText,forKey:"englishUpdateLastResult")
        let shouldNotify = automatic && newer && PetPreferences.shared.bool("automaticallyCheckUpdates")
        automatic = false; notify()
        // Failed startup checks are recorded in Settings, never presented as alerts.
        if shouldNotify {UpdateWindow.show(check:false,activate:false,automaticallyPresented:true)}
    }
    func cancel() {
        guard checking else {return}
        generation += 1; task?.cancel(); task = nil; session?.invalidateAndCancel(); session = nil
        checking = false; automatic = false; slow = false; slowTimer?.invalidate(); slowTimer = nil
        status = "Update check canceled"; notify()
    }
}

final class UpdateWindow: NSObject, NSWindowDelegate {
    private static var current: UpdateWindow?
    private let window = NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:400),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
    private let status = NSTextField(wrappingLabelWithString:"")
    private let explanation = NSTextField(wrappingLabelWithString:"")
    private let versions = NSTextField(labelWithString:"")
    private let timestamp = NSTextField(labelWithString:"")
    private let notes = AppTextView(frame:NSRect(x:0,y:0,width:540,height:220))
    private let notesScroll = GutterScrollView()
    private var notesHeight: NSLayoutConstraint!
    private let details = AppTextView(frame:NSRect(x:0,y:0,width:540,height:110))
    private let detailsScroll = GutterScrollView()
    private var detailsHeight: NSLayoutConstraint!
    private let detailsRow = NSStackView()
    private let disclosure = ActionButton("▸ Technical details") {}
    private let copyDetails = ActionButton("Copy Details") {}
    private var detailsExpanded = false
    private let spinner = NSProgressIndicator()
    private let retry = ActionButton("Check Again") {UpdateChecker.shared.check()}
    private let download = ActionButton("Open GitHub Releases") {}
    private let close = ActionButton("Close") {}
    private let disableAutomatic = ActionButton("Disable Automatic Update Checks") {}
    private let buttons = NSStackView()
    private let spacer = NSView()
    private var failedLayout: Bool?
    private var automaticPresentation = false
    private var automaticWindowWidth: CGFloat = 580
    static func show(check: Bool = true, activate: Bool = true, automaticallyPresented: Bool = false) {
        if current == nil {current = UpdateWindow()}
        guard let current else {return}
        current.automaticPresentation = automaticallyPresented
        if check {UpdateChecker.shared.check()}
        current.refresh()
        InterfaceWindows.shared.opened(current.window)
        if activate && current.window.isMiniaturized {current.window.deminiaturize(nil)}
        if activate {if !NSApp.isActive {NSApp.activate(ignoringOtherApps:true)}; current.window.makeKeyAndOrderFront(nil)}
        else if !current.window.isVisible && !current.window.isMiniaturized {current.window.orderFront(nil)}
    }
    override private init() {
        super.init()
        window.title = "Check for Updates"; window.isReleasedWhenClosed = false; window.delegate = self
        window.collectionBehavior = [.fullScreenNone]; window.standardWindowButton(.zoomButton)?.isEnabled = false
        let root = NSView(); window.contentView = root
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        status.font = .systemFont(ofSize:18,weight:.semibold)
        explanation.font = .systemFont(ofSize:13); explanation.textColor = .secondaryLabelColor
        versions.font = .systemFont(ofSize:12); timestamp.font = .systemFont(ofSize:11); timestamp.textColor = .secondaryLabelColor
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let heading = NSStackView(views:[spinner,status]); heading.spacing = 8
        for (scroll,text) in [(notesScroll,notes),(detailsScroll,details)] {
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
            text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
            text.minSize = .zero; text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.textContainer?.containerSize = NSSize(width:540,height:CGFloat.greatestFiniteMagnitude)
            text.textContainerInset = NSSize(width:4,height:4); scroll.documentView = text
        }
        details.font = .monospacedSystemFont(ofSize:11,weight:.regular)
        detailsRow.spacing = 10
        for view in [disclosure,NSView(),copyDetails] {detailsRow.addArrangedSubview(view)}
        disclosure.callback = { [weak self] in guard let self else {return}; self.detailsExpanded.toggle(); self.refresh() }
        CopyFeedback.attach(to:copyDetails) {UpdateChecker.shared.technicalDetails}
        close.callback = { [weak self] in self?.window.performClose(nil) }
        download.callback = {
            let url = UpdateChecker.shared.releaseURL ?? UpdateChecker.releases
            if !NSWorkspace.shared.open(url) {showError("Unable to open releases page",PetFailure(message:url.absoluteString))}
        }
        disableAutomatic.callback = { [weak self] in
            PetPreferences.shared.set(false,for:"automaticallyCheckUpdates")
            self?.window.performClose(nil)
        }
        buttons.spacing = 10
        automaticWindowWidth = max(580,[retry,disableAutomatic,close,download].reduce(CGFloat(80)) {$0 + $1.fittingSize.width})
        for view in [heading,explanation,versions,timestamp,notesScroll,detailsRow,detailsScroll,buttons] {stack.addArrangedSubview(view)}
        root.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20), stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-20),
            stack.topAnchor.constraint(equalTo:root.topAnchor,constant:20), stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16)
        ])
        for view in [heading,explanation,notesScroll,detailsRow,detailsScroll,buttons] {
            view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        }
        notesHeight = notesScroll.heightAnchor.constraint(equalToConstant:220)
        detailsHeight = detailsScroll.heightAnchor.constraint(equalToConstant:110)
        NotificationCenter.default.addObserver(self,selector:#selector(refresh),name:UpdateChecker.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAutomaticOption),name:PetPreferences.didChange,object:nil)
        window.center()
    }
    @objc private func refreshAutomaticOption() {
        disableAutomatic.isEnabled = PetPreferences.shared.bool("automaticallyCheckUpdates")
    }
    @objc private func refresh() {
        let checker = UpdateChecker.shared, failed = checker.failure != nil
        if failedLayout != failed {
            for view in buttons.arrangedSubviews {buttons.removeArrangedSubview(view); view.removeFromSuperview()}
            let views = failed ? [spacer,close,download,retry] : [retry,disableAutomatic,spacer,close,download]
            for view in views {buttons.addArrangedSubview(view)}
            failedLayout = failed; detailsExpanded = false
        }
        disableAutomatic.isHidden = !automaticPresentation
        refreshAutomaticOption()
        let width = automaticPresentation && !failed ? automaticWindowWidth : 580
        status.stringValue = checker.headline
        explanation.stringValue = checker.explanation; explanation.isHidden = checker.explanation.isEmpty
        let hasNotes = checker.release != nil && !failed
        notesHeight.isActive = hasNotes; notesScroll.isHidden = !hasNotes
        detailsRow.isHidden = !failed
        let showDetails = failed && detailsExpanded
        detailsHeight.isActive = showDetails; detailsScroll.isHidden = !showDetails
        copyDetails.isHidden = !showDetails
        disclosure.title = detailsExpanded ? "▾ Technical details" : "▸ Technical details"
        details.string = checker.technicalDetails
        let headingHeight = (checker.headline as NSString).boundingRect(with:NSSize(width:width-70,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:status.font!]).height
        let messageHeight = checker.explanation.isEmpty ? 0 : max(18,(checker.explanation as NSString).boundingRect(with:NSSize(width:width-40,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:explanation.font!]).height.rounded(.up))+12
        let height = max(24,headingHeight.rounded(.up)) + 136 + messageHeight + (hasNotes ? 232 : 0) + (failed ? 40 : 0) + (showDetails ? 122 : 0)
        let top = window.frame.maxY
        window.setContentSize(NSSize(width:width,height:height))
        window.setFrameOrigin(NSPoint(x:window.frame.minX,y:top-window.frame.height))
        versions.stringValue = "Current version \(Paths.version)" + (hasNotes ? " · Latest stable release \(checker.release!.tag_name)" : "")
        timestamp.stringValue = "Last checked: " + checker.lastCheckText
        retry.title = failed ? "Retry" : "Check Again"; retry.isEnabled = !checker.checking; retry.emphasize(failed)
        download.title = failed ? "View Releases" : "Open GitHub Releases"; download.emphasize(!failed)
        close.title = checker.checking ? "Cancel Check" : "Close"
        if checker.checking {spinner.startAnimation(nil)} else {spinner.stopAnimation(nil)}
        let body = checker.release?.body?.trimmingCharacters(in:.whitespacesAndNewlines)
        notes.textStorage?.setAttributedString(MarkdownText.render(body?.isEmpty == false ? body! : checker.release == nil ? "" : "No release notes provided for this version.",font:.systemFont(ofSize:13)))
    }
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.current = nil; UpdateChecker.shared.cancel()
    }
}
