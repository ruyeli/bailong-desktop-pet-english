import AppKit

// 默认目录只影响新会话；清理入口始终绑定应用内置 Workspace。
final class WorkspaceSettingsPage:NSObject {
    private let form:SettingsForm
    private unowned let window:NSWindow
    private let reload:() -> Void
    private let clear:(@escaping (Result<Void,Error>) -> Void) -> Void
    private var clearing = false
    init(form:SettingsForm,window:NSWindow,reload:@escaping () -> Void,clear:@escaping (@escaping (Result<Void,Error>) -> Void) -> Void) {
        self.form = form; self.window = window; self.reload = reload; self.clear = clear
    }
    func render() {
        let directory = form.preferences.defaultWorkspace
        let open = ActionButton("Open in Finder") {FinderFileReveal.openDirectory(directory)}
        let choose = ActionButton("Choose Folder…") { [weak self] in self?.chooseDirectory() }
        let actions = NSStackView(views:[open,choose]); actions.spacing = 8; actions.distribution = .fill
        let restore = ActionButton("Restore Built-in Folder") { [weak self] in
            guard let self else {return}
            self.form.preferences.reset(["defaultWorkspace"]); self.reload()
        }
        restore.isEnabled = !form.preferences.string("defaultWorkspace").isEmpty
        let cleanup = SettingsFooterButton(title:clearing ? "Cleaning…" : "Clean…",target:self,action:#selector(confirmClear))
        cleanup.bezelStyle = .rounded; cleanup.hasDestructiveAction = true; cleanup.isEnabled = !clearing
        form.group("Default workspace for pet chats",[
            form.row("Default workspace",detail:directory.path,control:actions),
            form.note("New chats in the default workspace use this folder. Existing chats retain their own workspaces. Changing this setting does not move files."),
            form.row("Restore built-in workspace",control:restore),
            form.row("Clean built-in workspace",detail:"Only the contents of the built-in folder below are moved to Trash. The folder and chat history remain. Custom workspaces are not cleaned.\n"+LocalStorage.workspace.path,control:cleanup)
        ])
    }
    private func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = form.preferences.defaultWorkspace; panel.prompt = "Set as Default Workspace"
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in
            guard let self,response == .OK,let directory = panel.url else {return}
            let path = directory.standardizedFileURL.path
            self.form.preferences.set(path == LocalStorage.workspace.path ? "" : path,for:"defaultWorkspace")
            self.reload()
        }
    }
    @objc private func confirmClear() {
        guard !clearing else {return}
        window.makeFirstResponder(nil)
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "Clean the built-in workspace?"
        alert.informativeText = "Move all files and subfolders here to Trash, including hidden files. Keep the folder and chat history. File links in history will no longer open at their original locations.\n\n"+LocalStorage.workspace.path
        alert.addButton(withTitle:"Cancel")
        alert.addButton(withTitle:"Move to Trash").hasDestructiveAction = true
        alert.beginDangerousSheet(for:window) { [weak self] response in
            guard let self,response == .alertSecondButtonReturn else {return}
            self.clearing = true; self.reload()
            self.clear { [weak self] result in
                guard let self else {return}
                self.clearing = false; self.reload()
                if case .failure(let error) = result {showError("Workspace cleanup incomplete",error)}
            }
        }
    }
}
