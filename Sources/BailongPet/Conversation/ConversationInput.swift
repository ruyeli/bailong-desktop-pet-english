import Foundation

enum ConversationKind:Int,CaseIterable {
    case persona, project
    var title:String {self == .persona ? "Pet Persona Chat" : "Codex Project Chat"}
    var symbol:String {self == .persona ? "bubble.left" : "folder"}
}
extension Conversation {
    var kind:ConversationKind {external ? .project : .persona}
}
enum ChatEntry:Hashable {case composer, history}

// 两个输入入口各自按会话保存文字，仅驻留内存。普通刷新不保存或覆盖输入。
final class ChatDraftCache {
    private var values = [ChatEntry:[String:String]]()
    private var targets = [ChatEntry:String]()
    func target(_ entry:ChatEntry) -> String? {targets[entry]}
    func select(_ key:String?,entry:ChatEntry,current:String) -> String? {
        guard targets[entry] != key else {return nil}
        if let old = targets[entry] {values[entry,default:[:]][old] = current}
        targets[entry] = key
        return key.flatMap {values[entry]?[$0]} ?? ""
    }
    func clearSubmitted(key:String,entry:ChatEntry,text:String) {
        if values[entry]?[key]?.trimmingCharacters(in:.whitespacesAndNewlines) == text {values[entry]?[key] = ""}
    }
    func forget(_ key:String) {
        for entry in [ChatEntry.composer,.history] {values[entry]?.removeValue(forKey:key)}
    }
    func clear() {values.removeAll(); targets.removeAll()}
}

// 两个界面共用的显示状态，不持有发送逻辑或改变任务生命周期。
struct ChatInputState {
    var conversation:Conversation?
    var kind:ConversationKind = .persona
    var runningTitle:String?
    var ownsRunningTask = false
    var stopping = false, executing = false, newConversation = false
    var sending = false, unconfirmed = false, readOnly = false
    var replyMode:DesktopReply.Mode?
    var modelSettings:DesktopReply.Settings?
    var modelNote:String?, replyNote:String?
    var desktopReady = false
    var canEdit:Bool {conversation != nil && runningTitle == nil && !sending && !readOnly}
    func canSend(models:ChatModelSettings) -> Bool {
        canEdit && !unconfirmed && (kind == .project ? desktopReady && conversation?.threadID != nil && replyMode != nil : !models.loading && models.error == nil)
    }
    var composerTitle:String {
        let preferences = PetPreferences.shared
        if stopping {return preferences.statusLine("taskStoppingTemplate")}
        if executing {return preferences.statusLine("conversationBusyTemplate")}
        if newConversation {return preferences.statusLine("conversationNewTemplate")}
        return preferences.fixedText("What can I help you with today, {userName}?")
    }
    var historyNote:String {
        if !note.isEmpty {return note}
        guard conversation != nil,kind == .persona else {return ""}
        return PetPreferences.shared.statusLine(newConversation ? "conversationNewTemplate" : "historyIdleTemplate")
    }
    var note:String {
        if readOnly {return "History is read-only: export the original file or reload it in Settings → Advanced"}
        if conversation == nil {return "Select a Codex project chat"}
        if sending {return "Sending…"}
        if unconfirmed {return "Delivery unconfirmed; draft retained"}
        if stopping {return PetPreferences.shared.statusLine("taskStoppingTemplate")}
        if ownsRunningTask {return PetPreferences.shared.statusLine("historyBusyTemplate")}
        if let runningTitle {return "Pet task running: "+runningTitle}
        if let replyNote {return replyNote}
        if kind == .project {return replyMode == .steer ? "Running · Send a follow-up" : replyMode == nil ? "This chat needs attention. Go to Codex." : ""}
        return ""
    }
}
