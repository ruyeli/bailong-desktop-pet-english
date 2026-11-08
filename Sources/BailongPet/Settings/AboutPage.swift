import AppKit

// 设置“关于”页保留原有图标、版本、原生分页和富文本链接；架构取编译目标。
final class AboutPageController: NSViewController {
    private static let repositoryURL = URL(string:"https://github.com/ruyeli/bailong-desktop-pet-english")!
    private var textViews = [NSTextView]()
    private let titleLabel = NSTextField(wrappingLabelWithString:"")
    private let appIcon = NSImageView()
    private let tabs = NSTabView()
    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Other architecture"
        #endif
    }

    init() {
        super.init(nibName:nil,bundle:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(updateAccent),name:AppAccent.didChange,object:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
        view = NSView()
        buildContent()
    }

    private func buildContent() {
        let root = view
        let icon = appIcon
        icon.image = AppIcons.application
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = titleLabel
        updateIdentity()
        title.maximumNumberOfLines = 0; title.lineBreakMode = .byWordWrapping
        title.font = .systemFont(ofSize:23,weight:.semibold)
        title.alignment = .center
        let version = NSTextField(labelWithString:"Version \(Paths.version) · \(Self.architecture)")
        version.font = .systemFont(ofSize:13)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        tabs.tabViewType = .topTabsBezelBorder; tabs.drawsBackground = false
        tabs.font = .systemFont(ofSize:13)
        for (identifier,label,text) in [("about","About",aboutText()),("credits","Open Source, Technology & Credits",creditsText())] {
            let item = NSTabViewItem(identifier:identifier)
            item.label = label
            item.view = readingView(text)
            tabs.addTabViewItem(item)
        }
        for view in [icon,title,version,tabs] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo:root.topAnchor,constant:20),
            icon.centerXAnchor.constraint(equalTo:root.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant:80), icon.heightAnchor.constraint(equalToConstant:80),
            title.topAnchor.constraint(equalTo:icon.bottomAnchor,constant:12),
            title.centerXAnchor.constraint(equalTo:root.centerXAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo:root.leadingAnchor,constant:24),
            title.trailingAnchor.constraint(lessThanOrEqualTo:root.trailingAnchor,constant:-24),
            version.topAnchor.constraint(equalTo:title.bottomAnchor,constant:6),
            version.centerXAnchor.constraint(equalTo:root.centerXAnchor),
            tabs.topAnchor.constraint(equalTo:version.bottomAnchor,constant:22),
            tabs.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),
            tabs.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),
            tabs.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-24)
        ])
    }

    func selectTab(_ identifier:String) {
        loadViewIfNeeded(); tabs.selectTabViewItem(withIdentifier:identifier)
    }

    private func readingView(_ content: NSAttributedString) -> NSScrollView {
        let scroll = GutterScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = LinkTextView(frame:NSRect(x:0,y:0,width:560,height:360))
        text.isEditable = false
        text.isSelectable = false
        // 说明文字不允许选中；链接通过点击手势打开，不依赖 NSTextView 的选择行为。
        text.addGestureRecognizer(NSClickGestureRecognizer(target:self,action:#selector(openTextLink(_:))))
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width:560,height:CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width:16,height:18)
        text.textStorage?.setAttributedString(content)
        textViews.append(text)
        scroll.documentView = text
        updateAccent()
        return scroll
    }

    @objc func updateIdentity() {
        let name = PetPreferences.shared.appName
        titleLabel.stringValue = name; titleLabel.hoverHelp = titleLabel.stringValue
        appIcon.setAccessibilityLabel(name+" app icon")
    }

    @objc private func openTextLink(_ gesture: NSClickGestureRecognizer) {
        guard let text = gesture.view as? NSTextView,
              let layout = text.layoutManager, let container = text.textContainer,
              let storage = text.textStorage, storage.length > 0 else {return}
        let location = gesture.location(in:text), origin = text.textContainerOrigin
        let point = NSPoint(x:location.x-origin.x,y:location.y-origin.y)
        let glyph = layout.glyphIndex(for:point,in:container)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange:NSRange(location:glyph,length:1),in:container).contains(point) else {return}
        let character = layout.characterIndexForGlyph(at:glyph)
        if let url = storage.attribute(.link,at:character,effectiveRange:nil) as? URL {NSWorkspace.shared.open(url)}
    }

    @objc private func updateAccent() {
        for text in textViews {
            text.linkTextAttributes = LinkAppearance.attributes
            text.needsDisplay = true
        }
    }

    private func aboutText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph("English edition by ruyeli. Original Swift port: Joseph Blue.",to:text)
        link("Upstream Swift port · Joseph Blue",url:"https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift",to:text)
        paragraph("An independently maintained, unofficial macOS port and native Swift + AppKit rewrite of GPT Bailong Desktop Pet by jingh12312-rgb (Feng Yin).",to:text)
        paragraph("Built with Swift and AppKit for native settings, chat history, and task interactions. Transparent animations use Apple system frameworks. Includes custom dialogue, message styling, 720×720 source quality, performance statistics, and local history.",to:text)
        link("Public repository · GitHub",url:Self.repositoryURL.absoluteString,to:text)
        paragraph("Connects to local Codex to start pet chats and follow desktop tasks. Check versions through GitHub releases from Settings → Updates or the app menu.",to:text)
        link("GitHub releases and update notes",url:UpdateChecker.releases.absoluteString,to:text)
        link("Original: GPT Bailong Desktop Pet · jingh12312-rgb (Feng Yin)",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)
        return text
    }

    private func creditsText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph("Thanks to the original creator and the projects below. Sources for the original work, assets, and software components are listed separately; each has its own licensing terms.",to:text,color:.secondaryLabelColor)

        heading("Original · GPT Bailong Desktop Pet",to:text)
        paragraph("Author: jingh12312-rgb (Feng Yin). Behavior and dialogue reference version 0.5.1. The original README states that no open-source license has been specified.",to:text)
        link("Original repository and documentation",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)

        heading("Character animation & app icon",to:text)
        paragraph("Character animations and the app icon originate from the original creator's v0.5.1 release.",to:text)

        heading("Native transparent animation",to:text)
        paragraph("HEVC with Alpha animations are decoded by AVFoundation, with CPU/vImage scaling and color conversion. PNG assets are converted using AVAssetWriter and Apple avconvert.",to:text)
        link("Apple HEVC with Alpha documentation",url:"https://developer.apple.com/videos/play/wwdc2019/506/",to:text)

        heading("SQLite · Local task records",to:text)
        paragraph("Uses the SQLite library provided by macOS, with no separate database runtime. SQLite places its published code and documentation in the public domain.",to:text)
        link("SQLite copyright information",url:"https://www.sqlite.org/copyright.html",to:text)

        heading("macOS UI design reference · macos-golden-gate-design",to:text)
        paragraph("Settings, sidebars, toolbars, and native control layouts reference gambadio's macos-golden-gate-design skill, licensed under MIT and used during design and review.",to:text)
        link("macos-golden-gate-design · GitHub",url:"https://github.com/gambadio/macos-golden-gate-design",to:text)

        heading("Technologies & system services",to:text)
        paragraph("Uses Swift, AppKit, Foundation, AVFoundation, Accelerate/vImage, Core Image, Core Graphics, and macOS system symbols. These system technologies are listed separately from third-party open-source components. Chat uses your installed Codex; Codex is not bundled with this app.",to:text)
        return text
    }

    private func paragraph(_ value: String,to text: NSMutableAttributedString,
                           color: NSColor = .labelColor,font: NSFont = .systemFont(ofSize:13)) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 12
        text.append(NSAttributedString(string:value+"\n",attributes:[.font:font,.foregroundColor:color,.paragraphStyle:style]))
    }
    private func heading(_ value: String,to text: NSMutableAttributedString) {
        paragraph(value,to:text,font:.systemFont(ofSize:15,weight:.semibold))
    }
    private func link(_ title: String,url: String,to text: NSMutableAttributedString) {
        let start = text.length
        paragraph(title,to:text)
        text.addAttributes(LinkAppearance.attributes(for:URL(string:url)!),range:NSRange(location:start,length:(title as NSString).length))
    }
}
