import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: PetController?, chat: ChatController?, sync: DesktopSync?
    var instanceFD: Int32 = -1
    var localEvents: Any?
    var terminationSignals = [DispatchSourceSignal]()
    var quitReady = false
    var terminationRequested = false
    var explicitQuit = false
    let lifecycle = RunLifecycle()
    var ownsInstance = false
    var unfinishedRun: RunLifecycle.UnfinishedRun?
    let revealName = Notification.Name("com.bailongpet.appkit.reveal.\(getuid())")
    func applicationDidFinishLaunching(_ notification: Notification) {
        TextContextMenu.install()
        AppAppearance.apply()
        if let icon = AppIcons.application {NSApp.applicationIconImage = icon}
        guard RosettaNotice.confirmLaunch() else {quitFromMenu(); return}
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(systemWillTerminate),name:NSWorkspace.willPowerOffNotification,object:nil)
        installTerminationSignals()
        installMenuBar()
        NotificationCenter.default.addObserver(self,selector:#selector(updateNames),name:PetPreferences.didChange,object:nil)
        RecoveryWindow.quit = { [weak self] in self?.quitFromMenu() }
        startApplication()
    }
    private func startApplication() {
        do {
            _ = try Paths.readVersion()
            try PetPreferences.shared.validatePlayback()
            if !ownsInstance {
                try FileManager.default.createDirectory(at:Paths.data,withIntermediateDirectories:true)
                instanceFD = open(Paths.data.appendingPathComponent("instance.lock").path,O_CREAT | O_RDWR,0o600)
                guard instanceFD >= 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
                if flock(instanceFD,LOCK_EX | LOCK_NB) != 0 {
                    let code = errno; close(instanceFD); instanceFD = -1
                    guard code == EWOULDBLOCK else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))}
                    DistributedNotificationCenter.default().postNotificationName(revealName,object:nil,userInfo:nil,deliverImmediately:true)
                    explicitQuit = true; NSApp.terminate(nil); return
                }
                ownsInstance = true; unfinishedRun = lifecycle.begin(version:Paths.version)
            }
            FollowSessions.clearManualExit()
            LoginLauncher.refreshExistingRegistration()
            FollowLauncher.refreshExistingRegistration()
            let pet = PetController(catalog:try Catalog.load()); self.pet = pet
            pet.onQuit = { [weak self] in self?.quitFromMenu() }
            localEvents = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown,.scrollWheel]) { [weak self, weak pet] event in
                if event.type == .keyDown, event.charactersIgnoringModifiers?.lowercased() == "q",
                   event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command {
                    self?.closeInterface(); return nil
                }
                pet?.interaction(); return event
            }
            DistributedNotificationCenter.default().addObserver(self,selector:#selector(reveal),name:revealName,object:nil)
            loadChat()
            RecoveryWindow.resolve("startup")
            if let previous = unfinishedRun {
                unfinishedRun = nil
                let started = previous.started?.formatted(date:.numeric,time:.standard) ?? "Not recorded"
                RecoveryWindow.show(id:"previous-run",report:RecoveryReport(title:"The previous session did not end normally",message:"The app has restarted. Check task status; unfinished tasks will not run again automatically.",module:"Run status",operation:"Check previous exit record",facts:["Last version: "+previous.version,"Last launch: "+started,"Exit reason: no normal exit was recorded. This does not distinguish a crash, forced quit, or power loss."]),actionTitle:"Continue") {RecoveryWindow.resolve("previous-run")}
            }
            if PetPreferences.shared.bool("automaticallyCheckUpdates") {UpdateChecker.shared.check(automatically:true)}
        } catch {
            RecoveryWindow.show(id:"startup",report:RecoveryReport(title:"App initialization incomplete",message:"Check that the data folder is writable and app resources are complete, then initialize again. Existing settings and history will be retained.",module:"App startup",operation:"Initialize data folder and assets",error:error),actionTitle:"Initialize Again") { [weak self] in self?.startApplication() }
        }
    }
    private func loadChat() {
        guard let pet,chat == nil else {return}
        do {
            let chat = try ChatController(pet:pet); self.chat = chat
            let sync = DesktopSync(chat:chat); self.sync = sync
            pet.settings.onClearLocalData = { [weak chat,weak sync] in
                guard let chat,let sync else {throw PetFailure(message:"Data management has stopped.")}
                try chat.clearLocalData(); sync.clearLocalProjection()
            }
            pet.syncDiagnostics = { [weak sync] in sync?.diagnostics ?? "Stopped" }
            pet.syncStatus = { [weak sync] in sync?.status ?? "Task synchronization has stopped. New task status is not being read." }
            RecoveryWindow.resolve("history-load")
        } catch {
            pet.syncDiagnostics = { "Conversation initialization incomplete" }
            pet.syncStatus = { "Conversation initialization is incomplete and task sync has not started. Open History to reload.\n\n"+error.localizedDescription }
            pet.bubble.taskProvider = {BubbleTaskOverview(status:"Task sync has not started. Open History to retry.")}
            pet.onHistory = { [weak self] _ in self?.loadChat(); RecoveryWindow.revealAll() }
            pet.onComposer = { [weak self] in self?.loadChat(); RecoveryWindow.revealAll() }
            RecoveryWindow.show(id:"history-load",report:RecoveryReport(title:"Unable to load conversation data",message:"The original history file is retained. Chats and task sync have not started. Correct the file format or read permissions, then reload.",module:"Conversation data",operation:"Read history and initialize workspace",error:error),actionTitle:"Reload") { [weak self] in self?.loadChat() }
        }
    }
    func installTerminationSignals() {
        // 在主队列走正常退出流程；不能在 POSIX 信号处理函数中调用 AppKit。
        for number in [SIGINT,SIGTERM] {
            signal(number,SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal:number,queue:.main)
            source.setEventHandler { [weak self] in
                guard let self, !self.terminationRequested else{return}
                self.terminationRequested = true
                if ProcessInfo.processInfo.environment["BAILONG_DEV_RUN"] == "1" {print("Quitting and cleaning up pet subprocesses…")}
                self.quitFromMenu()
            }
            terminationSignals.append(source); source.resume()
        }
    }
    func installMenuBar() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(); appItem.submenu = appMenu; bar.addItem(appItem)
        let about = NSMenuItem(title:"About "+PetPreferences.shared.appName,action:#selector(showAbout),keyEquivalent:""); about.target = self; about.tag = 101; appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(MenuAction("Check for Updates…",symbol:"arrow.triangle.2.circlepath") {UpdateWindow.show()})
        let settings = NSMenuItem(title:"Settings…",action:#selector(showSettings),keyEquivalent:","); settings.target = self
        settings.image = NSImage(systemSymbolName:"gearshape",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let close = NSMenuItem(title:"Close Current Window",action:#selector(closeInterface),keyEquivalent:"q"); close.target = self; appMenu.addItem(close)
        let closeWindow = NSMenuItem(title:"Close Window",action:#selector(closeInterface),keyEquivalent:"w"); closeWindow.target = self; appMenu.addItem(closeWindow)
        let quit = NSMenuItem(title:"Quit "+PetPreferences.shared.appName,action:#selector(quitFromMenu),keyEquivalent:""); quit.target = self; quit.tag = 102; quit.image = NSImage(systemSymbolName:"rectangle.portrait.and.arrow.right",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular)); appMenu.addItem(quit)
        let editItem = NSMenuItem(title:"Edit",action:nil,keyEquivalent:""); let edit = NSMenu(title:"Edit"); editItem.submenu = edit; bar.addItem(editItem)
        for (title,action,key) in [("Undo","undo:","z"),("Redo","redo:","Z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            edit.addItem(NSMenuItem(title:title,action:NSSelectorFromString(action),keyEquivalent:key))
        }
        let conversation = NSMenuItem(title:"Chat",action:nil,keyEquivalent:""); let commands = NSMenu(title:"Chat"); conversation.submenu = commands; bar.addItem(conversation)
        commands.addItem(MenuAction("Open Chat",symbol:"bubble.left.and.bubble.right") { [weak self] in self?.chat?.toggleComposer() })
        commands.addItem(MenuAction("New Chat") { [weak self] in self?.chat?.newConversation(); self?.chat?.showHistory(nil) })
        commands.addItem(MenuAction("Choose Workspace Folder…") { [weak self] in self?.chat?.chooseFolder() })
        commands.addItem(MenuAction("Chat History",symbol:"clock") { [weak self] in self?.chat?.showHistory(nil) })
        let windowsItem = NSMenuItem(title:"Window",action:nil,keyEquivalent:"")
        let windows = NSMenu(title:"Window"); windowsItem.submenu = windows; bar.addItem(windowsItem)
        windows.addItem(MenuAction("App Performance Monitor",symbol:"chart.xyaxis.line") { [weak self] in self?.pet?.showDiagnostics() })
        windows.addItem(MenuAction("Errors & Recovery",symbol:"exclamationmark.triangle") {RecoveryWindow.revealAll()})
        windows.addItem(NSMenuItem(title:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m"))
        windows.addItem(.separator()); NSApp.windowsMenu = windows
        bar.showProvidedImages(); NSApp.mainMenu = bar
    }
    @objc func updateNames() {
        let name = PetPreferences.shared.appName
        let menu = NSApp.mainMenu?.items.first?.submenu
        menu?.item(withTag:101)?.title = "About "+name
        menu?.item(withTag:102)?.title = "Quit "+name
    }
    @objc func showSettings() {pet?.showSettings()}
    @objc func showAbout() {pet?.showSettings(section:.about)}
    @objc func systemWillTerminate() {explicitQuit = true}
    @objc func quitFromMenu() {explicitQuit = true; FollowSessions.markManualExit(); NSApp.terminate(nil)}
    @objc func closeInterface() {
        // 原生模态窗口与 sheet 均走取消路径，不触发确认或危险操作。
        if let modal = NSApp.modalWindow {
            if let panel = modal as? NSSavePanel {panel.cancel(nil)}
            else {NSApp.abortModal(); modal.orderOut(nil)}
            return
        }
        let candidate = [NSApp.keyWindow,NSApp.mainWindow].compactMap {$0}.first {$0.isVisible || $0.isMiniaturized}
            ?? InterfaceWindows.shared.frontmost
        guard let window = candidate else {return}
        if let sheet = window.attachedSheet ?? (window.isSheet ? window : nil) {
            if let panel = sheet as? NSSavePanel {panel.cancel(nil)}
            else {sheet.sheetParent?.endSheet(sheet,returnCode:.cancel); sheet.orderOut(nil)}
        } else if window === chat?.ui.composer {chat?.ui.hideComposer()}
        else if window.styleMask.contains(.closable) {window.performClose(nil)}
        else if window.canBecomeKey {window.close()}
    }
    @objc func reveal() {
        if NSApp.isHidden {NSApp.unhideWithoutActivation()}
        pet?.revealFromReopen()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reveal()
        // 保留已有普通窗口召回，不重新打开已关闭的设置或历史。
        InterfaceWindows.shared.recall()
        return false
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(MenuAction("Settings…",symbol:"gearshape") { [weak self] in self?.pet?.showSettings() })
        menu.addItem(MenuAction("App Performance Monitor") { [weak self] in self?.pet?.showDiagnostics() })
        menu.addItem(MenuAction("Chat History",symbol:"clock") { [weak self] in self?.chat?.showHistory(nil) })
        if RecoveryWindow.hasIssues {menu.addItem(MenuAction("Errors & Recovery") {RecoveryWindow.revealAll()})}
        menu.addItem(MenuAction("Open Chat",symbol:"bubble.left.and.bubble.right") { [weak self] in self?.chat?.toggleComposer() })
        return menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Dock 的系统“退出”只关闭界面；完整退出必须来自桌宠的显式退出入口。
        if !explicitQuit {closeInterface(); return .terminateCancel}
        UpdateChecker.shared.cancel()
        if quitReady || chat == nil {return .terminateNow}
        sync?.close()
        if chat?.running == nil {chat?.shutdown {}; return .terminateNow}
        chat?.shutdown { [weak self] in self?.quitReady = true; NSApp.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        if ownsInstance {lifecycle.finish()}
        sync?.close(); pet?.close(); NotificationCenter.default.removeObserver(self); DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let localEvents {NSEvent.removeMonitor(localEvents)}
        if instanceFD >= 0 {close(instanceFD)}
    }
}
if CommandLine.arguments.contains("--follow") {FollowLauncher.run()}
else {
    // AppKit 原生 tooltip 的延迟单位为毫秒；仅写当前应用域。
    UserDefaults.standard.set(200,forKey:"NSInitialToolTipDelay")
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
}
