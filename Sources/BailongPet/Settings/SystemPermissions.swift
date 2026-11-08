import AppKit
import Carbon

enum FinderAutomationPermission {
    private static let queue = DispatchQueue(label:"Bailong Finder Authorization",qos:.userInitiated)
    enum State {
        case allowed, notRequested, denied, unavailable(OSStatus)
        var title:String {
            switch self {
            case .allowed:return "Allowed"
            case .notRequested:return "Not authorized"
            case .denied:return "Not allowed"
            case .unavailable(let code):return code == procNotFound ? "Finder is not running" : "Unable to read status (\(code))"
            }
        }
    }
    static func check(ask:Bool,completion:@escaping (State) -> Void) {
        queue.async {
            let target = NSAppleEventDescriptor(bundleIdentifier:"com.apple.finder")
            let code = AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,ask)
            let state:State
            switch code {
            case noErr:state = .allowed
            case OSStatus(errAEEventWouldRequireUserConsent):state = .notRequested
            case OSStatus(errAEEventNotPermitted):state = .denied
            default:state = .unavailable(code)
            }
            DispatchQueue.main.async {completion(state)}
        }
    }
}

enum SystemPermissionSettings {
    static func open(_ pane:String) {
        let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?"+pane)!
        if !NSWorkspace.shared.open(url) {showError("Unable to open System Settings",PetFailure(message:"Open System Settings → Privacy & Security."))}
    }
}

// 状态查询不请求授权；只有明确点击按钮才触发系统授权。
final class FinderPermissionControl:NSStackView {
    private let status = NSTextField(labelWithString:"Checking…")
    private var state:FinderAutomationPermission.State?
    private var checking = false
    private var button:ActionButton!
    override init(frame:NSRect) {
        super.init(frame:frame)
        orientation = .horizontal; alignment = .centerY; spacing = 8
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor
        button = ActionButton("Authorize…") { [weak self] in self?.performAction() }
        addArrangedSubview(status); addArrangedSubview(button)
        NotificationCenter.default.addObserver(self,selector:#selector(refresh(_:)),name:NSWindow.didBecomeKeyNotification,object:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); if window != nil {check(ask:false)}}
    @objc private func refresh(_ note:Notification) {if note.object as? NSWindow === window {check(ask:false)}}
    private func check(ask:Bool) {
        guard !checking else {return}
        checking = true; button.isEnabled = false
        FinderAutomationPermission.check(ask:ask) { [weak self] result in
            guard let self else {return}
            self.checking = false; self.state = result; self.status.stringValue = result.title
            self.status.setAccessibilityLabel("Finder automation: "+result.title)
            switch result {
            case .notRequested:self.button.title = "Authorize…"
            case .unavailable:self.button.title = "Check Again"
            default:self.button.title = "System Settings…"
            }
            self.button.isEnabled = true
        }
    }
    private func performAction() {
        switch state {
        case .allowed?,.denied?:SystemPermissionSettings.open("Privacy_Automation")
        case .notRequested?:check(ask:true)
        default:check(ask:false)
        }
    }
}
