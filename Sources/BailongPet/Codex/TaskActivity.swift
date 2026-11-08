import Foundation

struct TaskActivity:Equatable {
    enum Kind {case reasoning, tool, reply}
    let title:String
    var detail:String = ""
    var kind:Kind = .tool
    var finished = false
    var templateKey:String? = nil
    var text:String {detail.isEmpty ? title : title+"\n\n"+detail}
    var displayTitle:String {
        if let templateKey {return PetPreferences.shared.statusLine(templateKey)}
        return finished || kind == .reply ? title : PetPreferences.shared.statusLine(kind == .reasoning ? "taskThinkingTemplate" : "taskToolTemplate")
    }
    var actionTitle:String {kind == .tool && !finished && templateKey == nil ? title : ""}
    var line:String {
        let prefix = displayTitle
        let parts = [prefix,actionTitle,detail].filter {!$0.isEmpty}
        return parts.joined(separator:" · ").replacingOccurrences(of:"**",with:"").split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
    }
    var visible:Bool {kind == .reasoning ? PetPreferences.shared.bool("showThinkingProgress") : kind == .tool ? PetPreferences.shared.bool("showToolProgress") : true}
    static func summary(_ parts:[Any]) -> String {
        parts.compactMap {$0 as? String ?? ($0 as? [String:Any])?["text"] as? String}.filter {!$0.isEmpty}.joined(separator:"\n")
    }
    static func from(type:String,status:String?,summary:String = "",tool:String? = nil,command:String? = nil,
                     actions:[[String:Any]] = [],paths:[String] = []) -> TaskActivity? {
        // reasoning 项结束只表示这一段摘要结束，不能将仍在执行的轮次改成“思考摘要”。
        if type == "reasoning" {return .init(title:"Thinking",detail:summary,kind:.reasoning)}
        let labels = ["commandExecution":("Running a command","Command finished"),"fileChange":("Editing files","File edits ended"),
            "mcpToolCall":("Using tools","Tool call ended"),"dynamicToolCall":("Using tools","Tool call ended"),
            "webSearch":("Searching the web","Web search ended"),"imageGeneration":("Generating image","Image generation ended"),
            "imageView":("Viewing image","Viewed image"),"contextCompaction":("Compacting context","Context compaction ended")]
        guard let labels = labels[type] else {return nil}
        let ended = ["completed","failed","interrupted","cancelled","canceled","declined"].contains(status ?? "")
        var detail = type == "commandExecution" ? command ?? "" : tool ?? ""
        if type == "commandExecution",!actions.isEmpty {
            detail = actions.map { action in
                let path = action["path"] as? String ?? ""
                switch action["type"] as? String {
                case "read": return (ended ? "Read " : "Reading ")+(action["name"] as? String ?? path)
                case "listFiles": return (ended ? "Listed files" : "Listing files")+(path.isEmpty ? "" : " · "+path)
                case "search":
                    let query = action["query"] as? String ?? ""
                    return (ended ? "Search finished" : "Searching")+(query.isEmpty ? "" : "「"+query+"」")+(path.isEmpty ? "" : " · "+path)
                default: return action["command"] as? String ?? command ?? ""
                }
            }.filter {!$0.isEmpty}.joined(separator:"\n")
        }
        if type == "fileChange" {detail = paths.joined(separator:"\n")}
        if status == "failed" {detail = [labels.1,detail,"This call failed. The task has not reported completion."].filter {!$0.isEmpty}.joined(separator:" · ")}
        return .init(title:ended ? labels.1 : labels.0,detail:detail,finished:ended,
                     templateKey:status == "failed" ? "taskWarningTemplate" : type == "commandExecution" ? (ended ? "taskCommandCompletedTemplate" : "taskCommandTemplate") : nil)
    }
    static func from(item:[String:Any]) -> TaskActivity? {
        var status = item["status"] as? String
        if status == nil,(item["completed"] as? Bool == true || item["completedAtMs"] as? NSNumber != nil) {status = "completed"}
        let tool = [item["namespace"] as? String ?? item["server"] as? String,item["tool"] as? String].compactMap {$0}.filter {!$0.isEmpty}.joined(separator:".")
        return from(type:item["type"] as? String ?? "",status:status,summary:summary(item["summary"] as? [Any] ?? []),
                    tool:tool.isEmpty ? item["query"] as? String : tool,command:item["command"] as? String,
                    actions:item["commandActions"] as? [[String:Any]] ?? [],paths:(item["changes"] as? [[String:Any]] ?? []).compactMap {$0["path"] as? String})
    }
    static func current(items:[[String:Any]],replyTemplateKey:String = "taskReplyTemplate") -> TaskActivity? {
        var result:TaskActivity?, runningTool:TaskActivity?
        for item in items {
            let type = item["type"] as? String ?? ""
            if type == "agentMessage" {result = .init(title:"Replying",kind:.reply,templateKey:replyTemplateKey); continue}
            guard let next = from(item:item) else {continue}
            if next.kind == .tool,!next.finished,["inProgress","running"].contains(item["status"] as? String ?? "") {runningTool = next}
            // 连续的空 reasoning 项不擦掉此前同阶段已公开的摘要；工具/回复切换仍改变状态。
            if next.kind == .reasoning,next.detail.isEmpty,result?.kind == .reasoning,!((result?.detail.isEmpty) ?? true) {continue}
            result = next
        }
        return runningTool ?? result
    }
}
