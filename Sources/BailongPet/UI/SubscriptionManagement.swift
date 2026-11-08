import AppKit

enum SubscriptionManagement {
    case personal, organization, api, bedrock, gcp
    static func forAccount(_ account:[String:Any]?,plan:String) -> Self {
        switch account?["type"] as? String {
        case "apiKey":return .api
        case "amazonBedrock":return .bedrock
        case "gcp":return .gcp
        default:
            return ["Team","Business","Enterprise","Edu","Science"].contains(where:{plan.hasPrefix($0)}) ? .organization : .personal
        }
    }
    var title:String {self == .api || self == .bedrock || self == .gcp ? "Billing" : "Manage Subscription"}
    var destinations:[(String,String)] {
        switch self {
        case .personal:return [("ChatGPT Web Subscription","https://chatgpt.com/settings/billing"),("Google Play Subscriptions","https://play.google.com/store/account/subscriptions"),("Apple Subscriptions","https://apps.apple.com/account/subscriptions")]
        case .organization:return [("ChatGPT Workspace Management","https://chatgpt.com/")]
        case .api:return [("OpenAI API Billing","https://platform.openai.com/settings/organization/billing/overview")]
        case .bedrock:return [("AWS Billing","https://console.aws.amazon.com/billing/")]
        case .gcp:return [("Google Cloud Billing","https://console.cloud.google.com/billing")]
        }
    }
}

// 原生轻量文字按钮与 NSMenu；仅用户点击后打开官方页面，不读取网页账号或凭证。
final class SubscriptionManagementButton:NSButton {
    let management:SubscriptionManagement
    init(management:SubscriptionManagement,font:NSFont) {
        self.management = management
        super.init(frame:.zero)
        title = management.title; isBordered = false; bezelStyle = .inline
        self.font = font; alignment = .left; contentTintColor = AppAccent.color
        attributedTitle = NSAttributedString(string:management.title,attributes:[.font:font,.foregroundColor:AppAccent.color])
        image = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil)
        imagePosition = .imageTrailing; imageScaling = .scaleProportionallyDown
        target = self; action = #selector(openMenu); setAccessibilityLabel(management.title)
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func openMenu() {
        let menu = NSMenu()
        for (label,url) in management.destinations {
            let item = NSMenuItem(title:label,action:#selector(openDestination(_:)),keyEquivalent:"")
            item.target = self; item.representedObject = url; menu.addItem(item)
        }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:bounds.maxY),in:self)
    }
    @objc private func openDestination(_ sender:NSMenuItem) {
        guard let address = sender.representedObject as? String,let url = URL(string:address) else {return}
        NSWorkspace.shared.open(url)
    }
}
