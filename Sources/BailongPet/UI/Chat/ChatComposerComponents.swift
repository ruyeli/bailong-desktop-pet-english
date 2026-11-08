import AppKit

// 纯展示组件：会话选择、设置与操作由调用方持有。
final class ChatModeControl: NSSegmentedControl {
    var onSelect:(Int) -> Void = {_ in}
    init(labels:[String]) {
        super.init(frame:.zero)
        segmentCount = labels.count; trackingMode = .selectOne; segmentStyle = .rounded
        for (index,title) in labels.enumerated() {setLabel(title,forSegment:index)}
        selectedSegment = 0; target = self; action = #selector(changed)
        setAccessibilityLabel("Chat type")
        setContentHuggingPriority(.required,for:.horizontal)
    }
    required init?(coder:NSCoder) {fatalError()}
    func select(_ index:Int) {if selectedSegment != index {selectedSegment = index}}
    @objc private func changed() {onSelect(selectedSegment)}
}

final class ChatMetadataRow: NSStackView {
    init(_ title:String,content:NSView,accessory:NSView? = nil,expandsContent:Bool = false) {
        super.init(frame:.zero)
        orientation = .horizontal; alignment = .centerY; distribution = .fill; spacing = 8
        let caption = NSTextField(labelWithString:title)
        caption.font = .systemFont(ofSize:12); caption.textColor = .secondaryLabelColor
        caption.setContentCompressionResistancePriority(.required,for:.horizontal)
        addArrangedSubview(caption); addArrangedSubview(content)
        caption.widthAnchor.constraint(equalToConstant:("Workspace" as NSString).size(withAttributes:[.font:caption.font!]).width.rounded(.up)).isActive = true
        if let accessory {addArrangedSubview(accessory); accessory.setContentCompressionResistancePriority(.required,for:.horizontal)}
        if !expandsContent {addArrangedSubview(NSView()); content.setContentHuggingPriority(.defaultHigh,for:.horizontal)}
    }
    required init?(coder:NSCoder) {fatalError()}
}

// 临时输入与历史共用只读显示，不拥有连接、设置缓存或模型写入。
final class ChatReadOnlyModelField: ModelSummaryButton {
    init() {
        super.init(frame:.zero)
        isEnabled = false
        image = NSImage(systemSymbolName:"lock",accessibilityDescription:"Read-only"); imagePosition = .imageTrailing
        setAccessibilityRole(.staticText)
    }
    required init?(coder:NSCoder) {fatalError()}
    func update(settings:DesktopReply.Settings?,error:String?) {
        if let settings {
            let effort = settings.effort.map(ChatModelSettings.effortName) ?? "Not provided"
            title = ModelPresentation.summary(model:settings.model,effort:effort)+" · Read-only"
            let source = settings.effortFromHistory ? "Reasoning effort comes from the chat record." : ""
            hoverHelp = "Uses the original Codex chat settings, currently read-only."+source+"\nModel: "+settings.model+"\nReasoning effort: "+effort
        } else {
            title = error ?? "Reading Codex chat settings…"; hoverHelp = title
        }
        setAccessibilityLabel("Codex model and reasoning effort, read-only")
        setAccessibilityValue(title)
        setAccessibilityHelp(hoverHelp)
    }
}

final class ChatReplyPreview: NSTextField {
    private var sourceID:String?
    init() {
        super.init(frame:.zero)
        isEditable = false; isSelectable = false; isBezeled = false; drawsBackground = false
        font = .systemFont(ofSize:12); textColor = .secondaryLabelColor
        usesSingleLineMode = true; lineBreakMode = .byTruncatingTail
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    }
    required init?(coder:NSCoder) {fatalError()}
    func update(turn:Turn?) {
        let identity = turn?.bodyReference.id ?? ""
        guard sourceID != identity else {return}; sourceID = identity
        let body = turn?.bodyReference.value()
        let markdown = body.map {$0.final.isEmpty ? $0.messages : $0.final} ?? ""
        // 复用现有 Markdown 解析，仅生成显示摘要；历史仍保存原文。
        let plain = MarkdownText.render(markdown,font:font!).string.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        let excerpt = String(plain.prefix(180))+(plain.count > 180 ? "…" : "")
        stringValue = excerpt.isEmpty ? "" : "Latest reply: "+excerpt
        isHidden = excerpt.isEmpty
        hoverHelp = plain.isEmpty ? nil : String(plain.prefix(200))+(plain.count > 200 ? "..." : "")
        setAccessibilityLabel(stringValue)
    }
}

// 链接只负责路径显示和用户点击，打开目录交给调用方，不读取文件或会话数据。
final class WorkspaceLinkButton: NSButton,LinkCursorControl {
    var onOpen:(URL) -> Void = {_ in}
    private var directory:URL?
    private var displayedPath:String?
    init() {
        super.init(frame:.zero)
        isBordered = false; alignment = .left; font = .systemFont(ofSize:13)
        focusRingType = .exterior; target = self; action = #selector(openDirectory)
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        setAccessibilityLabel("Open workspace in Finder")
        update(path:"")
    }
    required init?(coder:NSCoder) {fatalError()}
    func update(path:String) {
        let color = path.isEmpty ? NSColor.secondaryLabelColor : AppAccent.color
        guard displayedPath != path || attributedTitle.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor != color else {return}
        displayedPath = path
        directory = path.isEmpty ? nil : URL(fileURLWithPath:path,isDirectory:true)
        isEnabled = directory != nil
        let text = path.isEmpty ? "No workspace selected" : (path as NSString).abbreviatingWithTildeInPath
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingMiddle
        var attributes:[NSAttributedString.Key:Any] = [.font:font!, .foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:paragraph]
        if isEnabled {attributes.merge(LinkAppearance.attributes) {_,link in link}}
        attributedTitle = NSAttributedString(string:text,attributes:attributes)
        hoverHelp = path.isEmpty ? nil : path
        setAccessibilityValue(path)
    }
    @objc private func openDirectory() {if let directory {onOpen(directory)}}
    override func resetCursorRects() {super.resetCursorRects(); if isEnabled {LinkAppearance.addCursorRect(bounds,to:self)}}
}
