import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsPanel: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate {
    let window = SettingsWindow(contentRect:NSRect(x:0,y:0,width:1040,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    let preferences: PetPreferences
    let catalog: Catalog?
    private lazy var form:SettingsForm = {
        let form = SettingsForm(content:content,preferences:preferences,window:window)
        form.petSymbol = { [weak self] in self?.petSymbol() }
        form.historyRecoveryReason = { [weak self] in self?.historyRecoveryReason() }
        return form
    }()
    private lazy var appearancePage = AppearanceSettingsPage(form:form,window:window,
        reload:{ [weak self] in self?.render() },onPreviewDetails:{ [weak self] in self?.onPreviewDetails() })
    private lazy var activityPage = ActivitySettingsPage(form:form,catalog:catalog,
        reload:{ [weak self] in self?.render() },onPreview:{ [weak self] in self?.onPreview($0) })
    private let aboutPage = AboutPageController()
    private lazy var workspacePage = WorkspaceSettingsPage(form:form,window:window,reload:{ [weak self] in self?.render() },clear:{ [weak self] completion in
        guard let action = self?.onClearDefaultWorkspace else {completion(.failure(PetFailure(message:"Conversation management is not ready. The workspace cannot be cleaned."))); return}
        action(completion)
    })
    private let splitController = NSSplitViewController()
    private let sidebar = NSTableView(), scroll = NSScrollView(), content = NSStackView()
    private let resetButton = SettingsFooterButton(title:"Reset this page to defaults",target:nil,action:nil)
    private weak var updateStatusLabel: NSTextField?
    private weak var updateTimeLabel: NSTextField?
    private let searchField = NSSearchField()
    private var searchItem:NSSearchToolbarItem?
    private let searchResults = SettingsSearchResults()
    private lazy var searchIndex = SettingsSearchEntry.all(catalog:catalog)
    private var searchHighlight:SettingsSearchHighlight?
    private var selected: SettingsSection = .general
    private var hasShown = false
    private var hasSavedFrame = false
    var petSymbol: () -> NSImage? = {nil}
    var onClose: () -> Void = {}
    var onPreview: (Clip) -> Void = { _ in }
    var onMessagePreview: (MessagePurpose) -> Void = { _ in }
    var onPreviewDetails: () -> Void = {}
    var onClearLocalData: (() throws -> Void)?
    var onClearDefaultWorkspace: ((@escaping (Result<Void,Error>) -> Void) -> Void)?
    var historyRecoveryReason:() -> String? = {nil}
    var onReloadHistory:(() throws -> Void)?
    var onExportHistory:((URL) throws -> Void)?
    var historyExportExtension:() -> String = {"json"}
    private var storageGeneration = 0
    init(preferences: PetPreferences = .shared, catalog: Catalog? = nil) {
        self.preferences = preferences; self.catalog = catalog
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(startupRegistrationChanged),name:FollowLauncher.didChange,object:nil)
        window.title = "Settings"; window.isReleasedWhenClosed = false; window.delegate = self
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenNone)
        window.minSize = NSSize(width:800,height:540)
        if let screen = NSScreen.main {window.setContentSize(NSSize(width:min(1040,screen.visibleFrame.width-80),height:min(900,screen.visibleFrame.height-80)))}
        window.focusSearch = { [weak self] in
            guard let self else {return}
            self.searchItem?.beginSearchInteraction(); self.window.makeFirstResponder(self.searchField)
        }
        searchResults.onOpen = { [weak self] in self?.revealSetting($0) }
        searchResults.onCancel = { [weak self] in self?.clearSearch(); self?.window.makeFirstResponder(self?.searchField) }
        let side = NSVisualEffectView(); side.material = .sidebar; side.blendingMode = .behindWindow
        side.state = .followsWindowActiveState
        let sideScroll = NSScrollView(); sideScroll.drawsBackground = false; sideScroll.hasVerticalScroller = true; sideScroll.autohidesScrollers = true
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("section")); sidebar.addTableColumn(column)
        sidebar.headerView = nil; sidebar.style = .plain; sidebar.rowHeight = 32; sidebar.backgroundColor = .clear
        sidebar.selectionHighlightStyle = .none; sidebar.intercellSpacing = .zero
        sidebar.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; sidebar.autoresizingMask = [.width]
        column.minWidth = 0; column.resizingMask = .autoresizingMask
        sideScroll.hasHorizontalScroller = false; sideScroll.horizontalScrollElasticity = .none
        sidebar.dataSource = self; sidebar.delegate = self; sidebar.allowsEmptySelection = false
        sidebar.setAccessibilityLabel("Settings categories"); sideScroll.documentView = sidebar
        side.addSubview(sideScroll)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let detail = NSView(), document = TopDownView(); scroll.documentView = document; detail.addSubview(scroll)
        let aboutView = aboutPage.view; aboutView.isHidden = true; aboutView.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(aboutView)
        searchResults.isHidden = true; searchResults.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(searchResults)
        NSLayoutConstraint.activate([
            searchResults.topAnchor.constraint(equalTo:detail.safeAreaLayoutGuide.topAnchor),searchResults.bottomAnchor.constraint(equalTo:detail.bottomAnchor),
            searchResults.leadingAnchor.constraint(equalTo:detail.leadingAnchor),searchResults.trailingAnchor.constraint(equalTo:detail.trailingAnchor)
        ])
        NSLayoutConstraint.activate([
            aboutView.topAnchor.constraint(equalTo:detail.safeAreaLayoutGuide.topAnchor),aboutView.bottomAnchor.constraint(equalTo:detail.bottomAnchor),
            aboutView.centerXAnchor.constraint(equalTo:detail.centerXAnchor),aboutView.widthAnchor.constraint(lessThanOrEqualToConstant:708),
            aboutView.leadingAnchor.constraint(greaterThanOrEqualTo:detail.leadingAnchor),aboutView.trailingAnchor.constraint(lessThanOrEqualTo:detail.trailingAnchor)
        ])
        let aboutWidth = aboutView.widthAnchor.constraint(equalTo:detail.widthAnchor); aboutWidth.priority = .defaultHigh; aboutWidth.isActive = true
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 24
        document.addSubview(content)
        resetButton.target = self; resetButton.action = #selector(restorePage); resetButton.focusRingType = .exterior
        let resetAll = SettingsFooterButton(title:"Reset all settings to defaults",target:self,action:#selector(restoreAll))
        resetAll.bezelStyle = .rounded; resetAll.hasDestructiveAction = true
        resetAll.focusRingType = .exterior
        let closeButton = SettingsFooterButton(title:"Close",target:window,action:#selector(NSWindow.performClose(_:)))
        closeButton.focusRingType = .exterior
        closeButton.setAccessibilityLabel("Close settings window")
        let footerLine = NSBox(); footerLine.boxType = .separator
        let sidebarFooter = NSStackView(views:[footerLine,resetButton,resetAll,closeButton])
        sidebarFooter.orientation = .vertical; sidebarFooter.spacing = 8; sidebarFooter.alignment = .leading
        for button in [resetButton as NSButton,resetAll,closeButton] {
            button.font = .systemFont(ofSize:11); button.controlSize = .small
            button.heightAnchor.constraint(equalToConstant:28).isActive = true
            button.widthAnchor.constraint(equalTo:sidebarFooter.widthAnchor).isActive = true
        }
        footerLine.widthAnchor.constraint(equalTo:sidebarFooter.widthAnchor).isActive = true
        side.addSubview(sidebarFooter); sidebarFooter.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([sidebarFooter.leadingAnchor.constraint(equalTo:side.leadingAnchor,constant:12),sidebarFooter.trailingAnchor.constraint(equalTo:side.trailingAnchor,constant:-12),sidebarFooter.bottomAnchor.constraint(equalTo:side.safeAreaLayoutGuide.bottomAnchor,constant:-12)])
        let navigation = NSViewController(); navigation.view = side
        let destination = NSViewController(); destination.view = detail
        let sidebarItem = NSSplitViewItem(sidebarWithViewController:navigation)
        sidebarItem.minimumThickness = 180; sidebarItem.maximumThickness = 260; sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true
        let detailItem = NSSplitViewItem(viewController:destination); detailItem.minimumThickness = 560
        splitController.addSplitViewItem(sidebarItem); splitController.addSplitViewItem(detailItem)
        splitController.splitView.dividerStyle = .thin
        window.contentViewController = splitController
        let toolbar = NSToolbar(identifier:"BailongSettingsToolbar"); toolbar.delegate = self; toolbar.displayMode = .iconOnly
        window.toolbar = toolbar; window.toolbarStyle = .unified
        for view in [sideScroll,scroll,document,content] {view.translatesAutoresizingMaskIntoConstraints = false}
        let preferredWidth = content.widthAnchor.constraint(equalTo:document.widthAnchor,constant:-48); preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            sideScroll.leadingAnchor.constraint(equalTo:side.leadingAnchor),sideScroll.trailingAnchor.constraint(equalTo:side.trailingAnchor),
            sideScroll.topAnchor.constraint(equalTo:side.safeAreaLayoutGuide.topAnchor,constant:8),sideScroll.bottomAnchor.constraint(equalTo:sidebarFooter.topAnchor,constant:-12),
            scroll.leadingAnchor.constraint(equalTo:detail.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:detail.trailingAnchor),
            scroll.topAnchor.constraint(equalTo:detail.safeAreaLayoutGuide.topAnchor),scroll.bottomAnchor.constraint(equalTo:detail.bottomAnchor),
            document.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),document.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            content.centerXAnchor.constraint(equalTo:document.centerXAnchor),content.widthAnchor.constraint(lessThanOrEqualToConstant:780),preferredWidth,
            content.leadingAnchor.constraint(greaterThanOrEqualTo:document.leadingAnchor,constant:24),content.trailingAnchor.constraint(lessThanOrEqualTo:document.trailingAnchor,constant:-24),
            content.topAnchor.constraint(equalTo:document.topAnchor,constant:24),content.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-24)
        ])
        splitController.splitView.setPosition(200,ofDividerAt:0)
        sidebar.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAccent),name:AppAccent.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshUpdateStatus),name:UpdateChecker.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshDiagnosticsSwitch),name:PetPreferences.didChange,object:preferences)
        render()
        window.center()
        hasSavedFrame = window.restoreSavedFrame(named:"BailongSettingsWindow")
    }
    @objc private func refreshDiagnosticsSwitch() {
        form.refreshAvailability()
        appearancePage.refreshAvailability()
    }
    func show(section: SettingsSection? = nil) {
        if let section {select(section)} else {render()}
        if !hasShown {
            if !hasSavedFrame {window.zoom(nil)}
            hasShown = true
        }
        InterfaceWindows.shared.opened(window)
        NSApp.addWindowsItem(window,title:window.title,filename:false)
        if window.isMiniaturized {window.deminiaturize(nil)}
        if !NSApp.isActive {NSApp.activate(ignoringOtherApps:true)}; window.makeKeyAndOrderFront(nil)
    }
    func select(_ section: SettingsSection) {clearSearch(); selected = section; sidebar.selectRowIndexes(IndexSet(integer:section.rawValue),byExtendingSelection:false); render()}
    func numberOfRows(in tableView: NSTableView) -> Int {SettingsSection.allCases.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {AccentHistoryRow()}
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = SettingsSection(rawValue:row)!
        let cell = HistoryConversationCell(title:section.title,symbol:section.symbol)
        cell.hoverHelp = nil
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {if let section = SettingsSection(rawValue:sidebar.selectedRow) {window.makeFirstResponder(nil); clearSearch(); selected = section; render()}}
    func windowWillClose(_ notification: Notification) {window.makeFirstResponder(nil); appearancePage.dismissPreview(); NSApp.removeWindowsItem(window); onClose()}
    func windowWillReturnFieldEditor(_ sender:NSWindow,to client:Any?) -> Any? {form.fieldEditor(for:client)}
    func controlTextDidChange(_ notification:Notification) {
        guard notification.object as? NSTextField === searchField else {return}
        searchSettings()
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {[.init("settings-sidebar"),.init("settings-divider"),.flexibleSpace,.init("settings-search")]}
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {toolbarAllowedItemIdentifiers(toolbar)}
    func toolbar(_ toolbar: NSToolbar,itemForItemIdentifier id: NSToolbarItem.Identifier,willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        if id.rawValue == "settings-search" {
            let item = NSSearchToolbarItem(itemIdentifier:id)
            searchField.placeholderString = "Search settings"; searchField.setAccessibilityLabel("Search individual settings")
            searchField.sendsSearchStringImmediately = true; searchField.delegate = self
            searchField.target = self; searchField.action = #selector(searchSettings)
            item.searchField = searchField; item.label = "Search settings"; item.preferredWidthForSearchField = 240
            searchItem = item
            return item
        }
        if id.rawValue == "settings-divider" {return NSTrackingSeparatorToolbarItem(identifier:id,splitView:splitController.splitView,dividerIndex:0)}
        guard id.rawValue == "settings-sidebar" else {return nil}
        let item = NSToolbarItem(itemIdentifier:id); item.label = "Show or hide sidebar"
        item.image = NSImage(systemSymbolName:"sidebar.left",accessibilityDescription:item.label)
        item.target = splitController; item.action = #selector(NSSplitViewController.toggleSidebar(_:)); item.isBordered = true; item.installHoverHelp()
        return item
    }
    @objc private func searchSettings() {
        if let editor = searchField.currentEditor() as? NSTextView,editor.hasMarkedText() {return}
        searchResults.show(SettingsSearchEntry.matching(searchField.stringValue,in:searchIndex))
        updateSearchPresentation()
    }
    private func updateSearchPresentation() {
        let searching = !searchField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        searchResults.isHidden = !searching
        scroll.isHidden = searching || selected == .about
        aboutPage.view.isHidden = searching || selected != .about
        resetButton.isEnabled = !searching && !selected.keys.isEmpty
        window.title = searching ? "Search settings" : selected.title
    }
    private func clearSearch() {
        searchField.stringValue = ""; searchResults.show([]); updateSearchPresentation()
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector) -> Bool {
        guard control === searchField,!textView.hasMarkedText(),!searchField.stringValue.isEmpty else {return false}
        switch selector {
        case #selector(NSResponder.moveDown(_:)): searchResults.focus(); return true
        case #selector(NSResponder.insertNewline(_:)): searchResults.openSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)): clearSearch(); return true
        default: return false
        }
    }
    private func revealSetting(_ entry:SettingsSearchEntry) {
        window.makeFirstResponder(nil); select(entry.section)
        if entry.section == .about {
            aboutPage.selectTab(entry.title == "About" ? "about" : "credits")
            return
        }
        window.contentView?.layoutSubtreeIfNeeded()
        guard let target = form.searchAnchors[entry.anchor] ?? form.searchAnchors[entry.group],let document = scroll.documentView else {return}
        let rect = target.convert(target.bounds,to:document)
        let y = max(0,min(rect.midY-scroll.contentView.bounds.height/2,document.bounds.height-scroll.contentView.bounds.height))
        scroll.contentView.scroll(to:NSPoint(x:0,y:y)); scroll.reflectScrolledClipView(scroll.contentView)
        let highlight = SettingsSearchHighlight(frame:target.bounds)
        highlight.autoresizingMask = [.width,.height]
        target.addSubview(highlight,positioned:.below,relativeTo:nil); searchHighlight = highlight
        NSAccessibility.post(element:target,notification:.layoutChanged)
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak highlight] in highlight?.removeFromSuperview() }
    }
    @objc private func refreshAccent() {
        func update(_ view: NSView) {
            if let slider = view as? NSSlider {slider.trackFillColor = AppAccent.color}
            if let well = view as? NSColorWell {well.color = AppAccent.color}
            if let menu = view as? NSPopUpButton, menu.identifier?.rawValue == "accentStyle" {menu.selectItem(at:AppAccent.choices.firstIndex {$0.0 == preferences.string("accentStyle")} ?? 0)}
            for child in view.subviews {update(child)}
        }
        if let root = window.contentView {update(root)}
        appearancePage.refreshAccent()
        sidebar.enumerateAvailableRowViews { [weak self] row,index in
            row.needsDisplay = true
            let cell = self?.sidebar.view(atColumn:0,row:index,makeIfNecessary:false) as? NSTableCellView
            cell?.backgroundStyle = row.interiorBackgroundStyle
        }
    }
    @objc private func startupRegistrationChanged() {
        if selected == .general && window.isVisible {render()}
    }
    private func render() {
        guard window.contentView != nil else {return}
        searchHighlight?.removeFromSuperview(); searchHighlight = nil
        appearancePage.reset()
        form.reset(section:selected)
        window.title = selected.title
        resetButton.isEnabled = !selected.keys.isEmpty
        scroll.isHidden = selected == .about; aboutPage.view.isHidden = selected != .about
        switch selected {
        case .general: general()
        case .identity: IdentitySettingsPage.render(form:form,catalog:catalog,window:window,onPreview:onMessagePreview,reload:{ [weak self] in self?.render() })
        case .activity: activityPage.render()
        case .messages: MessageSettingsPage.render(form:form,onPreview:onMessagePreview)
        case .appearance: appearancePage.render()
        case .advanced: advanced()
        case .updates: updates()
        case .about: break
        case .developer:
            form.group("Animations", [form.choice("Quality", "animationQuality", [("720", "Original\t720×720"), ("512", "High\t512×512"), ("384", "Medium\t384×384"), ("256", "Low\t256×256")]),
                form.choice("Animation frame rate limit", "animationFPSLimit", [("full", "Full frame rate (≥ 24 FPS)"), ("20", "20 FPS"), ("15", "15 FPS")]),
                form.bufferFrames(),
                form.toggle("Preload entire animations", "preloadWholeAnimation", detail: "Loads the entire animation before playback and substantially increases memory (RAM) use. Not recommended.")])
            form.group("App statistics", [form.toggle("Show floating performance monitor", "showDiagnostics")])
        }
        scroll.contentView.scroll(to:.zero)
        updateSearchPresentation()
    }
    private func general() {
        if let notice = preferences.compatibilityNotice ?? SettingsStorage.compatibilityNotice {
            form.group("Settings compatibility",[form.note(notice),form.row("Compatibility record",control:ActionButton("Export…") { [weak self] in self?.exportCompatibilitySettings() })])
        }
        let login = SMAppService.mainApp.status
        let loginText = LoginLauncher.statusText
        form.group("Startup",[
            form.row("Launch at login",detail:loginText,control:ActionButton(login == .enabled ? "Disable…" : login == .requiresApproval ? "Open Login Items…" : "Enable…") { [weak self] in self?.configureLogin() }),
            form.row("Launch with Codex",detail:FollowLauncher.statusText,control:ActionButton("Configure…") { [weak self] in FollowLauncher.configure(); self?.render() }),
            form.toggle("Show pet on launch","showOnLaunch"),form.toggle("Remember last position","rememberPosition")])
        form.group("Permissions & System Settings",[
            form.row("Finder automation",detail:"Restore the minimized Finder window containing the file and select it.",control:FinderPermissionControl(frame:.zero)),
            form.row("Files & folders",detail:"macOS requests access to protected folders such as Documents, Desktop, and Downloads as needed. Permissions are managed per folder.",control:ActionButton("System Settings…") {SystemPermissionSettings.open("Privacy_FilesAndFolders")}),
            form.row("Login items & background activity",detail:"Manage launch at login and launch with Codex. Current status appears under Startup above.",control:ActionButton("Open Login Items…") {SMAppService.openSystemSettingsLoginItems()}),
            form.note("This app does not require Accessibility, Input Monitoring, Screen Recording, Camera, Microphone, or Full Disk Access permissions.")])
        var displays = [("","Follow current screen")] + NSScreen.screens.map {(PetPreferences.displayID($0),$0.localizedName)}
        let saved = preferences.string("preferredDisplay")
        if !displays.contains(where:{$0.0 == saved}) {displays.append((saved,"Disconnected display (using current screen)"))}
        form.group("Desktop",[form.toggle("Hide automatically in full screen","autoFullscreen"),form.choice("Display","preferredDisplay",displays)])
    }
    private func configureLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {showError("Configure launch at login from the app bundle",PetFailure(message:"Development scripts do not register login items. Use the built .app.")); return}
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try LoginLauncher.setEnabled(false)
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try LoginLauncher.setEnabled(true)
            }
            render()
        } catch {showError("Unable to configure launch at login",error)}
    }
    @objc private func refreshUpdateStatus() {
        updateStatusLabel?.stringValue = UpdateChecker.shared.recordText
        updateTimeLabel?.stringValue = UpdateChecker.shared.lastCheckText
    }
    private func updates() {
        let checkUpdate = ActionButton("Check for Updates…") {UpdateWindow.show()}; checkUpdate.emphasize()
        form.group("Version",[form.row("Current version",control:label(Paths.version)),
            form.row("Check stable releases",control:checkUpdate),
            form.row("Public repository",control:ActionButton("GitHub Releases") {
                if !NSWorkspace.shared.open(UpdateChecker.releases) {showError("Unable to open releases page",PetFailure(message:UpdateChecker.releases.absoluteString))}
            })])
        form.group("Automatic updates",[form.toggle("Check for updates on launch","automaticallyCheckUpdates",detail:"Notify when a new version is available. Failed checks are recorded on this page.")])
        let status = form.note(UpdateChecker.shared.recordText), time = label(UpdateChecker.shared.lastCheckText)
        updateStatusLabel = status; updateTimeLabel = time
        form.group("Update history",[form.row("Last checked",control:time),status])
    }
    private func advanced() {
        workspacePage.render()
        if let reason = historyRecoveryReason() {
            form.group("History recovery",[form.note(reason),
                form.row("Export original history file",control:ActionButton("Export…") { [weak self] in self?.exportOriginalHistory() }),
                form.row("Reload History",control:ActionButton("Reload") { [weak self] in
                    guard let self else {return}
                    do {try self.onReloadHistory?(); self.render()} catch {showError("History is still read-only",error)}
                })])
        }
        form.group("Settings files",[form.row("Export settings",detail:"Export app settings, excluding chat history and model preferences.",control:ActionButton("Export…") { [weak self] in self?.exportSettings() }),form.row("Import settings",detail:"All fields are checked before import. Login items are not changed by settings files.",control:ActionButton("Import…") { [weak self] in self?.importSettings() })])
        let data = label("Calculating…"), work = label("Calculating…"), cache = label("Calculating…")
        let total = label("Calculating this app's disk usage…")
        total.font = .systemFont(ofSize:11); total.textColor = .secondaryLabelColor
        total.identifier = .init("settings-explanation")
        let dataButton = SettingsFooterButton(title:"Clear This App's Local Data…",target:self,action:#selector(clearLocalData))
        let cacheButton = SettingsFooterButton(title:"Clear Cache…",target:self,action:#selector(clearLocalCache))
        for button in [dataButton,cacheButton] {button.bezelStyle = .rounded; button.hasDestructiveAction = true}
        form.group("Local storage used by this app",[total,
            form.row("This app's local data",detail:"Chat history, synced copies, and app settings",control:data),
            form.row("Built-in workspace",control:work),
            form.row("Disk cache",control:cache),
            form.row("Clear this app's local data",control:dataButton),form.row("Clear disk cache",control:cacheButton),
            form.row("Data folder",detail:Paths.data.path,control:ActionButton("Show in Finder") {if !NSWorkspace.shared.open(Paths.data) {showError("Unable to open data folder",PetFailure(message:Paths.data.path))}})],
            action:ActionButton("Refresh") { [weak self] in self?.render() })
        storageGeneration += 1; let generation = storageGeneration
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let result = Result {try LocalStorage.usage()}
            DispatchQueue.main.async {
                guard let self, self.storageGeneration == generation, self.selected == .advanced else {return}
                switch result {
                case .success(let usage):
                    total.stringValue = "Total: "+ByteCountFormatter.string(fromByteCount:usage.total,countStyle:.file)+" · Percentages are based on the three categories below"
                    data.stringValue = usage.description(usage.data); work.stringValue = usage.description(usage.workspace); cache.stringValue = usage.description(usage.cache)
                case .failure(let error):
                    total.stringValue = "Calculation failed: "+error.localizedDescription
                    for field in [data,work,cache] {field.stringValue = "Not available"}
                }
            }
        }
    }
    @objc private func clearLocalData() {
        confirmStorage(title:"Clear this app's local data?",body:"Delete this app's chat history and local Codex copies, and reset its settings. Workspace files, original Codex history, and sign-in information are retained.",button:"Clear this app's local data") { [weak self] in
            guard let action = self?.onClearLocalData else {throw PetFailure(message:"Data management is not ready.")}
            try action()
        }
    }
    @objc private func clearLocalCache() {
        confirmStorage(title:"Clear disk cache?",body:"Delete this app's disk cache. It will be regenerated as needed. Chat history, settings, and animation assets are retained.",button:"Clear Cache") {try LocalStorage.clearCache()}
    }
    private func confirmStorage(title:String,body:String,button:String,action:@escaping () throws -> Void) {
        window.makeFirstResponder(nil)
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = title; alert.informativeText = body
        alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:button).hasDestructiveAction = true
        alert.beginDangerousSheet(for:window) { [weak self] response in
            guard response == .alertSecondButtonReturn else {return}
            do {try action(); self?.render()} catch {showError("Cleanup incomplete",error)}
        }
    }
    @objc private func restorePage() {window.makeFirstResponder(nil); preferences.reset(selected.keys); render(); if selected == .appearance {appearancePage.showPreview()} else if selected == .identity {onMessagePreview(.preview)}}
    @objc private func restoreAll() {
        window.makeFirstResponder(nil); appearancePage.dismissPreview()
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "Reset all settings to defaults?"
        alert.informativeText = "All app settings will return to their defaults. Chat history, animation assets, and system login items are retained."
        alert.addButton(withTitle:"Cancel")
        let confirm = alert.addButton(withTitle:"Reset All Settings")
        confirm.hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = "\u{1b}"; confirm.keyEquivalent = ""
        alert.beginDangerousSheet(for:window) { [weak self] response in guard response == .alertSecondButtonReturn, let self else {return}; self.preferences.reset(Array(PetPreferences.defaults.keys)); self.render() }
    }
    private func exportCompatibilitySettings() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Bailong-settings-compatibility.json"
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in
            guard response == .OK,let url = panel.url,let self else {return}
            do {
                var values = [String:Any]()
                let source = SettingsStorage.compatibilityNotice == nil ? self.preferences.defaults : UserDefaults(suiteName:SettingsStorage.domain)!
                for key in PetPreferences.defaults.keys {if let value = source.object(forKey:key) {values[key] = value}}
                let original = self.preferences.defaults.dictionary(forKey:"compatibilityRecoveredValues") ?? [:]
                values.merge(original) {_,old in old}
                try JSONSerialization.data(withJSONObject:["settings":values,"schemaVersion":source.integer(forKey:SettingsStorage.schemaKey)],options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)
            } catch {showError("Unable to export compatibility record",error)}
        }
    }
    private func exportOriginalHistory() {
        let ext = historyExportExtension()
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension:ext) ?? .data]; panel.nameFieldStringValue = "Bailong-original-history."+ext
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in
            guard response == .OK,let url = panel.url,let self else {return}
            do {try self.onExportHistory?(url)} catch {showError("Unable to export original history file",error)}
        }
    }
    private func exportSettings() {
        window.makeFirstResponder(nil)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = PetPreferences.productName+"settings.json"
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in guard response == .OK, let url = panel.url, let self else {return}; do {try self.preferences.exportData().write(to:url,options:.atomic)} catch {showError("Unable to export settings",error)} }
    }
    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else {return}
            do {try self.preferences.importData(Data(contentsOf:url),clipIDs:Set(self.catalog?.all.map(\.id) ?? [])); self.render()}
            catch {showError("Unable to import settings",error)}
        }
    }
}
