import AppKit

// 菜单只装配现有动作，不拥有动画、手势或任务状态。
enum PetMenu {
    static func make(for pet:PetController,includeVisibility:Bool = false,random:@escaping () -> Void) -> NSMenu {
        let menu = NSMenu(); menu.delegate = pet
        if includeVisibility {
            let visibility = MenuAction("") { [weak pet] in
                guard let pet else {return}
                if pet.hidden || NSApp.isHidden {
                    if NSApp.isHidden {NSApp.unhideWithoutActivation()}
                    pet.revealFromReopen()
                } else {pet.manualHidden = true; pet.applyVisibility()}
            }
            visibility.identifier = .init("petVisibility")
            menu.addItem(visibility); menu.addItem(.separator())
            refreshVisibility(in:menu,pet:pet)
        }
        func submenu(_ title:String,symbol:String) -> NSMenu {
            let item = NSMenuItem(title:title,action:nil,keyEquivalent:"")
            item.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
            item.image?.isTemplate = true
            let child = NSMenu(title:title); item.submenu = child; menu.addItem(item); return child
        }
        menu.addItem(MenuAction("Open Chat",symbol:"bubble.left.and.bubble.right") { [weak pet] in pet?.onComposer() })
        menu.addItem(MenuAction("Chat History",symbol:"book.closed") { [weak pet] in pet?.onHistory(nil) })
        menu.addItem(MenuAction("Check Usage",symbol:"gauge.with.dots.needle.50percent") { [weak pet] in pet?.soundOnce(); pet?.onQuota() })
        let codex = MenuAction("Go to Codex") {CodexConnection.openDesktop()}
        codex.image = AppIcons.openAI?.copy() as? NSImage
        codex.image?.size = NSSize(width:16,height:16)
        menu.addItem(codex)
        menu.addItem(.separator())
        menu.addItem(MenuAction("Introduce Myself",symbol:"hand.wave") { [weak pet] in
            guard let pet, let clip = pet.catalog.variants.first(where: {$0.id == "01"}) else {return}
            pet.preview(clip)
        })
        menu.addItem(MenuAction("Random Animation",symbol:"shuffle") {random()})
        let animations = submenu("Play Animation",symbol:"play.rectangle")
        for (name,clips) in [("Idle animations",pet.catalog.idles+pet.catalog.extras),("Interaction animations",pet.catalog.variants),("Work animations",pet.catalog.work),("Movement animations",pet.catalog.movementAnimations)] {
            let item = NSMenuItem(title:name,action:nil,keyEquivalent:""), group = NSMenu(title:name)
            for clip in clips {group.addItem(MenuAction(clip.title) { [weak pet] in pet?.preview(clip) })}
            item.submenu = group; animations.addItem(item)
        }
        let switches = submenu("Quick Toggles",symbol:"switch.2")
        switches.addItem(MenuAction("Autonomous movement",checked:pet.autoMove) { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.autoMove,for:"autoMove") })
        switches.addItem(MenuAction("Play sound effects",checked:pet.soundEnabled) { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.soundEnabled,for:"soundEnabled") })
        switches.addItem(MenuAction("Task bubble alerts",checked:pet.taskBubbles) { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.taskBubbles,for:"taskBubbles") })
        switches.addItem(MenuAction("Hide automatically in full screen",checked:pet.autoFullscreen) { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.autoFullscreen,for:"autoFullscreen") })
        switches.addItem(.separator())
        switches.addItem(MenuAction("Startup Settings…",symbol:"power") { [weak pet] in pet?.showSettings(section:.general) })
        menu.addItem(.separator())
        menu.addItem(MenuAction("Change Pet, Bubble & Text Size…",symbol:"textformat.size") { [weak pet] in pet?.showSettings(section:.appearance) })
        menu.addItem(MenuAction("Change Names & Dialogue…",symbol:"person.text.rectangle") { [weak pet] in pet?.showSettings(section:.identity) })
        menu.addItem(MenuAction("Settings…",symbol:"gearshape") { [weak pet] in pet?.showSettings() })
        let tools = submenu("Tools & Help",symbol:"questionmark.circle")
        tools.addItem(MenuAction("Task Sync Status…",symbol:"arrow.triangle.2.circlepath") { [weak pet] in guard let pet else{return}; let a = NSAlert(); a.messageText = "Codex Task Sync Status"; a.informativeText = pet.syncStatus(); a.icon = NSImage(systemSymbolName:"arrow.triangle.2.circlepath",accessibilityDescription:"Task sync"); a.addButton(withTitle:"Got It"); a.applyAccent(); a.runModal() })
        tools.addItem(MenuAction("Performance Monitor…",symbol:"chart.xyaxis.line") { [weak pet] in pet?.showDiagnostics() })
        tools.addItem(.separator())
        tools.addItem(MenuAction("Check for Updates…",symbol:"arrow.down.circle") {UpdateWindow.show()})
        tools.addItem(MenuAction("About "+pet.preferences.appName+"…",symbol:"info.circle") { [weak pet] in pet?.showSettings(section:.about) })
        menu.addItem(.separator())
        menu.addItem(MenuAction("Quit "+pet.preferences.appName,symbol:"rectangle.portrait.and.arrow.right") { [weak pet] in pet?.onQuit() })
        menu.showProvidedImages()
        return menu
    }
    static func refreshVisibility(in menu:NSMenu,pet:PetController) {
        guard let item = menu.items.first,item.identifier?.rawValue == "petVisibility" else {return}
        let show = pet.hidden || NSApp.isHidden
        item.title = show ? "Show Pet" : "Hide Pet"
        item.image = NSImage(systemSymbolName:show ? "eye" : "eye.slash",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
        item.image?.isTemplate = true
    }
}
