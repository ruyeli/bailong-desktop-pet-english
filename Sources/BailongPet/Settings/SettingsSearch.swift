import AppKit

final class SettingsWindow: NSWindow {
    private var restoredFrame:NSRect?
    func restoreSavedFrame(named name:String) -> Bool {
        // 保存标准尺寸作为绿灯恢复目标，再读取用户保存的窗口位置与尺寸。
        restoredFrame = frame
        let restored = setFrameUsingName(name)
        setFrameAutosaveName(name)
        return restored
    }
    override func zoom(_ sender:Any?) {
        guard let area = screen?.visibleFrame else {return}
        if frame.equalTo(area),let restoredFrame {setFrame(restoredFrame,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion); self.restoredFrame = nil}
        else {restoredFrame = frame; setFrame(area,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)}
    }
    var focusSearch: () -> Void = {}
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command,.shift,.option,.control]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {focusSearch(); return true}
        return super.performKeyEquivalent(with:event)
    }
}

struct SettingsSearchEntry {
    let section:SettingsSection
    let group:String
    let title:String
    var keywords = ""
    var condition = ""
    var anchor:String {group+"/"+title}
    var location:String {section.title+" › "+group}

    // 索引只保存设置文案，不创建页面或触发预览、磁盘统计、登录项查询。
    static func all(catalog:Catalog?) -> [Self] {
        var entries = [Self]()
        func add(_ section:SettingsSection,_ group:String,_ titles:[String],_ keywords:String = "") {
            entries += titles.map {Self(section:section,group:group,title:$0,keywords:keywords)}
        }
        add(.general,"Startup",["Launch at login","Launch with Codex","Show pet on launch","Remember last position"],"startup login follow recall")
        add(.general,"Permissions & System Settings",["Finder automation"],"permission authorize Finder file links minimize restore automation system settings")
        add(.general,"Permissions & System Settings",["Files & folders"],"permission authorize Documents Desktop Downloads privacy file access system settings")
        add(.general,"Permissions & System Settings",["Login items & background activity"],"permission approval startup login follow background system settings")
        add(.general,"Desktop",["Hide automatically in full screen","Display"],"screen multiple displays")
        add(.identity,"What we call each other",["Your name","Pet name","Nickname"],"owner nickname user name variable")
        add(.identity,"Greeting",["Greeting line"],"dialogue welcome preview")
        add(.identity,"Task status lines",["Task in progress"],"dialogue template monitoring progress")
        add(.identity,"Task status lines",["New progress"],"dialogue template progress task plan stages Codex project tasks")
        add(.identity,"Task status lines",["Waiting for input","Waiting for approval","Task completed","Task failed","Task interrupted or canceled"],"dialogue approval template")
        add(.identity,"Task status lines",["Thinking","Using tools","Running a command","Command finished"],"dialogue template thinking summary tool calls commands terminal progress bubbles")
        for line in ConversationLines.task {add(.identity,"Task status lines",[line.title],"dialogue template "+line.text)}
        for line in ConversationLines.interface {add(.identity,"Chat window lines",[line.title],"dialogue template "+line.text)}
        add(.identity,"Usage check lines",["Checking usage"],"usage dialogue")
        add(.activity,"Mouse interaction",["Single-click pet","Double-click pet","Double right-click pet"],"click quick chat usage history task progress random animation")
        add(.activity,"Autonomous activity",["Activity level","Activity interval","Autonomous movement","Movement range","Reduce repeated animations","Overall playback speed"],"animation frequency quiet lively speed idle docked task previous random")
        add(.activity,"Task animations",["Play task opening animation","Celebrate completed tasks"],"Animations")
        add(.messages,"Progress reminders",["Remind me when progress stalls","Reminder interval"],"task running no progress 90 seconds 5 minutes timer waiting dialogue")
        add(.messages,"History",["Save history"],"chat save sync")
        add(.messages,"In-bubble approvals",["Approval button order"],"approve allow once allow turn deny reject left right order red cross green check")
        add(.messages,"Message cards & task overview",["Message cards to keep","Show task overview with interactions","Recent completed tasks"],"messages history previous next running recent completed")
        add(.messages,"Message types",["Show thinking summaries","Show tool calls"],"thinking summary tools operations status progress pop-ups automatic display toggle")
        add(.messages,"Task bubbles",["Thinking & tool progress pop-ups"],"automatic progress pop-ups enabled 2 seconds thinking tools short bubbles")
        add(.messages,"Input shortcut",["Sending & new lines"],"Enter Control Ctrl Command Shift Option alternative default send newline quick reply follow-up questionnaire")
        add(.messages,"Task bubbles",["Show task bubbles","Task messages","Final replies"],"task bubbles progress notification display toggle")
        add(.messages,"Message types",["Interaction lines"],"notifications display toggle")
        add(.messages,"Display duration",["Interaction lines","Task messages","Final replies","Usage information","Allow more reading time for long replies","Pause countdown on hover","Preview final reply bubble"],"bubble auto close seconds duration hover preview task progress")
        add(.messages,"Display duration",["Thinking & tool progress pop-ups"],"progress pop-up duration thinking tools auto-close seconds")
        add(.messages,"Sound",["Play sound effects"],"Sound")
        add(.messages,"Quiet companionship",["Enable quiet companionship now","Schedule quiet companionship","Start time","End time"],"quiet companionship schedule focus do not disturb night mute")
        add(.appearance,"Size",["Pet size","Bubble size","Message font size"],"scale font size typeface")
        add(.appearance,"Pet outline",["Outline shadow"],"pet outline glow shadow edges")
        add(.appearance,"Bubble shape",["Custom aspect ratio","Width : Height"],"bubble aspect ratio width height shape layout")
        add(.appearance,"Theme",["Appearance mode","Accent color","Custom"],"theme colors light dark system segmented")
        add(.appearance,"Message windows",["Message window material","Use system Liquid Glass settings","Glass opacity","Motion effects","Bubble effects"],"liquid glass plain segmented transparency frosted background animation preview")
        add(.advanced,"Settings files",["Export settings","Import settings"],"backup restore")
        add(.advanced,"Default workspace for pet chats",["Default workspace","Restore built-in workspace","Clean built-in workspace"],"persona new chat default directory folder Workspace select Finder trash clean workspace")
        add(.advanced,"Local storage used by this app",["This app's local data","Built-in workspace","Disk cache","Clear this app's local data","Clear disk cache","Data folder"],"storage disk space clean delete Finder default workspace local data")
        add(.developer,"Animations",["Quality","Animation frame rate limit","Animation buffer frames","Preload entire animations"],"performance memory RAM 720 512 384 256 FPS resolution buffer stutter frames")
        add(.developer,"App statistics",["Show floating performance monitor"],"CPU GPU memory RAM Swap performance monitor")
        add(.updates,"Version",["Current version","Check stable releases","Public repository"],"updates download GitHub releases")
        add(.updates,"Automatic updates",["Check for updates on launch"],"automatic new version")
        add(.updates,"Update history",["Last checked"],"updates check result")
        add(.about,"About",["About","Open Source, Technology & Credits"],"credits sources authors licenses technology AppKit macOS UI skill")
        for index in entries.indices {
            if ["Use system Liquid Glass settings","Glass opacity"].contains(entries[index].title) {
                entries[index].condition = "Shown when Liquid Glass is selected"
            } else if entries[index].section == .appearance && entries[index].title == "Custom" {
                entries[index].condition = "Shown when a custom accent color is selected"
            } else if entries[index].section == .appearance && entries[index].title == "Width : Height" {
                entries[index].condition = "Applies when custom aspect ratio is enabled"
            } else if entries[index].section == .activity && entries[index].title == "Movement range" {
                entries[index].condition = "Available when autonomous movement is enabled"
            } else if entries[index].section == .messages {
                switch (entries[index].group,entries[index].title) {
                case (_,"Start time"),(_,"End time"):
                    entries[index].condition = "Available when scheduled quiet companionship is enabled"
                case ("Progress reminders","Remind me when progress stalls"):
                    entries[index].condition = "Enable task bubbles and task messages to adjust"
                case ("Progress reminders","Reminder interval"):
                    entries[index].condition = "Enable task bubbles, task messages, and stalled-progress reminders to adjust"
                case (_,"Recent completed tasks"):
                    entries[index].condition = "Available when task overview is enabled"
                case ("Task bubbles","Task messages"),("Task bubbles","Final replies"):
                    entries[index].condition = "Available when task bubbles are enabled"
                case ("Task bubbles","Thinking & tool progress pop-ups"):
                    entries[index].condition = "Enable task bubbles and task messages to adjust"
                case ("Display duration","Task messages"):
                    entries[index].condition = "Enable task bubbles and task messages to adjust"
                case ("Display duration","Final replies"),("Display duration","Allow more reading time for long replies"):
                    entries[index].condition = "Enable task bubbles and final replies to adjust"
                case ("Display duration","Thinking & tool progress pop-ups"):
                    entries[index].condition = "Enable task bubbles, task messages, and progress pop-ups to adjust"
                case ("Display duration","Interaction lines"):
                    entries[index].condition = "Available when interaction lines are enabled"
                default: break
                }
            }
        }
        if let catalog {
            add(.identity,"Interaction lines",(catalog.variants+catalog.work).filter {$0.line != nil}.map(\.title),"dialogue template")
            for (group,clips) in [("Idle animations",catalog.idles+catalog.extras),("Interaction animations",catalog.variants),("Work animations",catalog.work),("Movement animations",catalog.movementAnimations),("Mouse & usage animations",[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation])] {
                add(.activity,group,clips.map(\.title),"animation playback speed frequency favorite preview")
            }
        }
        return entries
    }
    static func matching(_ query:String,in entries:[Self]) -> [Self] {
        let words = query.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        guard !words.isEmpty else {return []}
        let matches = entries.filter {entry in
            let text = [entry.title,entry.location,entry.keywords].joined(separator:" ")
            return words.allSatisfy {text.localizedStandardContains($0)}
        }
        return matches.filter {$0.title.localizedStandardContains(query)} + matches.filter {!$0.title.localizedStandardContains(query)}
    }
}

private final class SettingsSearchTable: NSTableView {
    var open:() -> Void = {}
    var cancel:() -> Void = {}
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {open(); return}
        if event.keyCode == 53 {cancel(); return}
        super.keyDown(with:event)
    }
}

final class SettingsSearchResults: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = SettingsSearchTable()
    private let caption = NSTextField(labelWithString:"")
    private let empty = NSTextField(labelWithString:"No settings found")
    private var entries = [SettingsSearchEntry]()
    var onOpen:(SettingsSearchEntry) -> Void = {_ in}
    var onCancel:() -> Void = {}
    init() {
        super.init(frame:.zero)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        table.addTableColumn(NSTableColumn(identifier:.init("setting")))
        table.headerView = nil; table.style = .plain; table.backgroundColor = .clear; table.rowHeight = 62
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.autoresizingMask = [.width]
        table.intercellSpacing = .zero; table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(openSelection)
        table.setAccessibilityLabel("Settings search results")
        table.open = { [weak self] in self?.openSelection() }; table.cancel = { [weak self] in self?.onCancel() }
        scroll.documentView = table
        caption.font = .systemFont(ofSize:12,weight:.medium); caption.textColor = .secondaryLabelColor
        empty.font = .systemFont(ofSize:14); empty.textColor = .secondaryLabelColor
        for view in [caption,scroll,empty] {view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)}
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo:leadingAnchor,constant:24),caption.topAnchor.constraint(equalTo:topAnchor,constant:20),
            scroll.topAnchor.constraint(equalTo:caption.bottomAnchor,constant:12),scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),scroll.bottomAnchor.constraint(equalTo:bottomAnchor),
            empty.centerXAnchor.constraint(equalTo:centerXAnchor),empty.topAnchor.constraint(equalTo:caption.bottomAnchor,constant:40)
        ])
    }
    required init?(coder:NSCoder) {fatalError()}
    func show(_ values:[SettingsSearchEntry]) {
        entries = values; caption.stringValue = "\(values.count) results"; empty.isHidden = !values.isEmpty
        table.reloadData()
        if !values.isEmpty {table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false); table.scrollRowToVisible(0)}
    }
    func focus() {window?.makeFirstResponder(table)}
    @objc func openSelection() {
        guard entries.indices.contains(table.selectedRow) else {return}
        onOpen(entries[table.selectedRow])
    }
    func numberOfRows(in tableView:NSTableView) -> Int {entries.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let entry = entries[row], cell = NSTableCellView()
        let title = NSTextField(labelWithString:entry.title)
        title.font = .systemFont(ofSize:13,weight:.medium)
        let path = NSTextField(labelWithString:entry.location+(entry.condition.isEmpty ? "" : " · "+entry.condition))
        path.font = .systemFont(ofSize:11); path.textColor = .secondaryLabelColor
        for field in [title,path] {field.lineBreakMode = .byTruncatingTail}
        let arrow = NSImageView(image:NSImage(systemSymbolName:"chevron.right",accessibilityDescription:nil)!)
        arrow.contentTintColor = .tertiaryLabelColor
        for view in [title,path,arrow] {view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view)}
        cell.hoverHelp = entry.title+"\n"+path.stringValue
        cell.textField = title; cell.setAccessibilityLabel(entry.title+", "+path.stringValue)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:12),title.topAnchor.constraint(equalTo:cell.topAnchor,constant:11),
            path.leadingAnchor.constraint(equalTo:title.leadingAnchor),path.topAnchor.constraint(equalTo:title.bottomAnchor,constant:5),
            arrow.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-12),arrow.centerYAnchor.constraint(equalTo:cell.centerYAnchor),arrow.widthAnchor.constraint(equalToConstant:12),
            title.trailingAnchor.constraint(lessThanOrEqualTo:arrow.leadingAnchor,constant:-12),path.trailingAnchor.constraint(lessThanOrEqualTo:arrow.leadingAnchor,constant:-12)
        ])
        return cell
    }
}

final class SettingsSearchHighlight: NSView {
    override func hitTest(_ point:NSPoint) -> NSView? {nil}
    override func draw(_ dirtyRect:NSRect) {
        AppAccent.color.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:6,yRadius:6).fill()
    }
}
