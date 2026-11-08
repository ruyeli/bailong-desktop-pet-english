import AppKit

enum IdentitySettingsPage {
    static func render(form:SettingsForm,catalog:Catalog?,window:NSWindow,onPreview:@escaping (MessagePurpose) -> Void,reload:@escaping () -> Void) {
        let preferences = form.preferences
        form.fill(form.note("{userName} is your name; {petName} is the pet's name. {nickname} uses the text below, or your name when blank. Right-click a dialogue or nickname field to insert variables."),in:form.content)
        let names = [form.text("Your name","ownerName",placeholder:"Defaults to Friend"),form.text("Pet name","petName",placeholder:"Bailong"),form.text("Nickname","customAddress",placeholder:"Leave blank to use your name; variables supported")]
        form.group("What we call each other",names)
        let preview = label(preferences.statusLine("greetingTemplate")); preview.font = .systemFont(ofSize:15,weight:.medium); form.identityPreview = preview
        form.group("Greeting",[form.text("Greeting line","greetingTemplate",limit:120),form.alignedRow(leading:preview,control:ActionButton("Preview Message") {onPreview(.preview)})])
        form.group("Task status lines",ConversationLines.task.map {form.text($0.title,$0.key,limit:ConversationLines.limit($0.key))} + [form.text("Task in progress","taskProgressTemplate",limit:120),form.text("New progress","taskUpdateTemplate",limit:120),form.text("Thinking","taskThinkingTemplate",limit:120),form.text("Using tools","taskToolTemplate",limit:120),form.text("Running a command","taskCommandTemplate",limit:120),form.text("Command finished","taskCommandCompletedTemplate",limit:120),form.text("Waiting for input","taskAnswerTemplate",limit:120),form.text("Waiting for approval","taskApprovalTemplate",limit:120),form.text("Task completed","taskSuccessTemplate",limit:120),form.text("Task failed","taskFailureTemplate",limit:120),form.text("Task interrupted or canceled","taskInterruptedTemplate",limit:120)])
        form.group("Chat window lines",ConversationLines.interface.map {form.text($0.title,$0.key,limit:120)})
        form.group("Usage check lines",[form.text("Checking usage","quotaLoadingTemplate",limit:120)])
        if let catalog {
            let lines = (catalog.variants+catalog.work).filter {$0.line != nil}
            let restore = ActionButton("Restore Defaults") { [weak window] in
                window?.makeFirstResponder(nil)
                preferences.set([String:String](),for:"customLines"); reload()
            }
            restore.controlSize = .small; restore.font = .systemFont(ofSize:11)
            restore.setAccessibilityLabel("Restore all interaction lines to defaults")
            form.group("Interaction lines",lines.map {clip in form.entry(clip.title,value:(preferences.value("customLines") as? [String:String])?[clip.id] ?? "",emptyFallback:clip.defaultLine ?? "",limit:120) {preferences.setLine($0,for:clip.id)}},action:restore)
        }
    }
}
