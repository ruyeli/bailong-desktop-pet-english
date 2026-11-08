import Foundation

// 默认值、编辑控件、恢复范围和搜索共用同一份台词定义。
enum ConversationLines {
    struct Entry {let key:String; let title:String; let text:String}
    static let task:[Entry] = [
        .init(key:"taskReceivedTemplate",title:"Pet chat task received",text:"Got it, {userName}! I'll get right to work."),
        .init(key:"taskReplyTemplate",title:"Pet chat replying",text:"{userName}, I'm writing a reply…"),
        .init(key:"desktopTaskReceivedTemplate",title:"Codex task received",text:"Got it, {userName}! I'll start working on your Codex task."),
        .init(key:"taskSteeringTemplate",title:"Follow-up received",text:"Got your follow-up, {userName}! I'll include it as I work."),
        .init(key:"taskStoppingTemplate",title:"Stopping task",text:"{userName}, I'm wrapping things up…"),
        .init(key:"taskStoppedTemplate",title:"Task stopped",text:"I've stopped for now, {userName}."),
        .init(key:"taskWarningTemplate",title:"Step failed",text:"{userName}, there's something you should know.")]
    static let interface:[Entry] = [
        .init(key:"conversationNewTemplate",title:"New chat ready",text:"Your new chat is ready, {userName}."),
        .init(key:"conversationBusyTemplate",title:"Quick chat busy",text:"{userName}, I'm working on it…"),
        .init(key:"historyBusyTemplate",title:"History window busy",text:"I'm working, {userName}. Progress will appear here."),
        .init(key:"historyIdleTemplate",title:"History window idle",text:"Your messages are saved on this Mac, {userName}"),
        .init(key:"conversationEmptyTemplate",title:"Empty chat greeting",text:"I'm here, {userName}! Write what you'd like to do below, and we can get started.")]
    static var keys:[String] {(task+interface).map(\.key)}
    static var defaults:[String:Any] {Dictionary(uniqueKeysWithValues:(task+interface).map {($0.key,$0.text as Any)})}
    static func limit(_ key:String) -> Int {key == "desktopTaskReceivedTemplate" ? 240 : 120}
    static func migrateReceivedLine(_ values:[String:Any]) -> [String:Any] {
        var values = values
        let titleKey = "desktopTaskReceivedTemplate", bodyKey = "desktopTaskReceivedBodyTemplate"
        guard values[bodyKey] == nil || values[bodyKey] is String else {return values}
        let oldTitle = "{userName}，我收到啦！", oldBody = "这就认真帮你处理 Codex 里的任务。"
        let title = values[titleKey] as? String, body = values[bodyKey] as? String
        if body != nil || title == oldTitle {
            let heading = title?.isEmpty == false ? title! : oldTitle
            let detail = body?.isEmpty == false ? body! : oldBody
            values[titleKey] = heading == oldTitle && detail == oldBody
                ? defaults[titleKey] : heading + detail
        }
        values.removeValue(forKey:bodyKey)
        return values
    }
}
