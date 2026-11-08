import AppKit

enum TaskAttentionKind: String {
    case answer, approval
    var templateKey: String {self == .answer ? "taskAnswerTemplate" : "taskApprovalTemplate"}
    var status: String {self == .answer ? "waitingForInput" : "waitingForApproval"}
}
struct TaskQuestionOption: Equatable {
    let title: String
    let detail: String?
    let recommended: Bool
}
struct TaskQuestion: Equatable {
    let prompt: String
    let options: [TaskQuestionOption]
    var id: String = ""
}
struct TaskAttention {
    let kind: TaskAttentionKind
    let body: String
    var isSensitive = false
    var questions: [TaskQuestion] = []
    static func question(_ question: [String:Any]) -> TaskAttention {
        if question["isSecret"] as? Bool == true {
            return TaskAttention(kind:.answer,body:"Sensitive information is required. Continue in the secure input window.",isSensitive:true)
        }
        let prompt = question["question"] as? String ?? question["title"] as? String ?? "Provide more information."
        let options = (question["options"] as? [Any] ?? []).compactMap {value -> TaskQuestionOption? in
            let object = value as? [String:Any]
            guard let title = value as? String ?? object?["label"] as? String else {return nil}
            // 推荐标签只来自原数据标记或原始名称，不根据位置推断。
            let suffixes = [" (Recommended)","（推荐）"," (推荐)"]
            let suffix = suffixes.first {title.hasSuffix($0)}
            return TaskQuestionOption(title:suffix.map {String(title.dropLast($0.count))} ?? title,
                detail:object?["description"] as? String,
                recommended:object?["recommended"] as? Bool == true || suffix != nil)
        }
        return TaskAttention(kind:.answer,body:([prompt]+options.map {"• "+$0.title+($0.recommended ? " (Recommended)" : "")+($0.detail.map {": "+$0} ?? "")}).joined(separator:"\n"),
            questions:[TaskQuestion(prompt:prompt,options:options,id:question["id"] as? String ?? "")])
    }

    static func approval(fileChange: Bool, reason: String?) -> TaskAttention {
        let action = fileChange ? "Waiting for permission to edit files." : "Waiting for permission to run an operation."
        return TaskAttention(kind:.approval,body:[action,reason ?? ""].filter {!$0.isEmpty}.joined(separator:"\n"))
    }
}

struct AppFailure {
    let title: String, message: String, detail: String
    var openDesktop = false
    static func animation(_ error: Error) -> AppFailure {
        AppFailure(title:"This animation cannot play right now",message:"The pet will keep its current image. Retry or choose another animation from the menu.",detail:error.localizedDescription)
    }
    static func codex(_ raw: String) -> AppFailure {
        if raw.contains("already has an active writer") {
            return AppFailure(title:"This chat already has a writer connection",message:"Continue in the original Codex chat, or start a new pet chat.",detail:raw,openDesktop:true)
        }
        return AppFailure(title:"Codex task did not complete",message:"View technical details. You can return to the input field, edit, and send again.",detail:raw)
    }

    func showDetails() {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        let scroll = GutterScrollView(frame:NSRect(x:0,y:0,width:480,height:180))
        let text = AppTextView(frame:scroll.bounds); text.isEditable = false; text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize:11,weight:.regular); text.string = detail
        text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.hasVerticalScroller = true; alert.accessoryView = scroll
        alert.addButton(withTitle:"Close"); alert.addButton(withTitle:"Copy Details")
        alert.applyAccent(primary:1,keyboardDefault:1)
        CopyFeedback.attach(to:alert.buttons[1]) {self.detail}
        alert.runModal()
    }
}

// 显示数据保持可选值：额度缺失不等于零，也不等于不限额。
struct QuotaRow {
    let title: String, value: String, detail: String?
    let remaining: Double?
}
struct QuotaOverview {
    let plan: String
    var rows: [QuotaRow]
    var notice: String?
    var management:SubscriptionManagement = .personal
}
enum QuotaPresentation {
    static let plans = ["free":"Free", "go":"Go", "plus":"Plus", "prolite":"Pro 100", "pro":"Pro 200", "promax":"Pro 500",
        "team":"Team", "business":"Business", "self_serve_business_prolite":"Business Premium", "self_serve_business_usage_based":"Business (pay-as-you-go)",
        "ent26":"Enterprise", "enterprise":"Enterprise", "enterprise_cbp_automation":"Enterprise (automation)", "enterprise_cbp_usage_based":"Enterprise (pay-as-you-go)",
        "edu":"Edu", "edu_plus":"Edu Plus", "edu_pro":"Edu Pro", "sci":"Science", "sci_plus":"Science Plus"]
    static func string(_ value: Any?) -> String? {
        guard let text = value as? String else {return nil}
        let result = text.trimmingCharacters(in:.whitespacesAndNewlines)
        return result.isEmpty || ["null","<null>"].contains(result.lowercased()) ? nil : result
    }
    static func number(_ value: Any?) -> Double? {
        // JSON 的整数和浮点值统一经 NSNumber 读取；Swift 字典中的 Int 也适用。
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {return nil}
        return value.doubleValue
    }
    static func plan(_ value: Any?, account: [String:Any]?) -> String {
        let supplied = string(value), accountPlan = string(account?["planType"])
        let raw = supplied == nil || supplied == "unknown" ? accountPlan ?? supplied : supplied
        if let raw {return plans[raw] ?? (raw == "unknown" ? "Unrecognized plan" : "Plan: "+raw)}
        switch account?["type"] as? String {
        case "apiKey": return "API pay-as-you-go"
        case "amazonBedrock": return "Amazon Bedrock"
        case "gcp": return "Google Cloud Vertex AI"
        default: return "Plan information unavailable"
        }
    }
    static func reset(_ value: Any?) -> String? {
        number(value).map {"Resets: "+Date(timeIntervalSince1970:$0).formatted(date:.abbreviated,time:.shortened)}
    }
    static func overview(_ value: [String:Any], account: [String:Any]?) -> QuotaOverview {
        let map = value["rateLimitsByLimitId"] as? [String:[String:Any]] ?? [:]
        var buckets = map.keys.sorted {a,b in a == "codex" && b != "codex" || a != "codex" && b != "codex" && a < b}.compactMap {map[$0]}
        if buckets.isEmpty, let legacy = value["rateLimits"] as? [String:Any] {buckets = [legacy]}
        let bucketPlan = buckets.compactMap {string($0["planType"])}.first(where:{$0 != "unknown"})
        var result = QuotaOverview(plan:plan(bucketPlan,account:account),rows:[])
        result.management = .forAccount(account,plan:result.plan)
        for (index,bucket) in buckets.enumerated() {
            let name = string(bucket["limitName"]) ?? string(bucket["limitId"]) ?? "Usage group \(index+1)"
            let prefix = buckets.count > 1 ? name+" · " : ""
            let before = result.rows.count
            for key in ["primary","secondary"] {
                guard let window = bucket[key] as? [String:Any] else {continue}
                let period: String
                if let minutes = number(window["windowDurationMins"]) {
                    period = minutes == 10080 ? "Weekly limit" : minutes.truncatingRemainder(dividingBy:60) == 0 ? String(format:"%.0f-hour limit",minutes/60) : String(format:"%.0f-minute limit",minutes)
                } else {period = key == "primary" ? "Primary limit" : "Secondary limit"}
                let remaining = number(window["usedPercent"]).map {max(0,min(100,100-$0))}
                result.rows.append(QuotaRow(title:prefix+period,value:remaining.map {String(format:"%.0f%% remaining",$0)} ?? "Not provided yet",detail:reset(window["resetsAt"]) ?? "Reset time not provided yet",remaining:remaining))
            }
            if let limit = bucket["individualLimit"] as? [String:Any] {
                let remaining = number(limit["remainingPercent"]).map {max(0,min(100,$0))}
                let amounts = [string(limit["used"]).map {"Used "+$0},string(limit["limit"]).map {"Limit "+$0}].compactMap {$0}.joined(separator:" / ")
                let detail = [amounts.isEmpty ? nil : amounts,reset(limit["resetsAt"])].compactMap {$0}.joined(separator:"\n")
                result.rows.append(QuotaRow(title:prefix+"Personal usage limit",value:remaining.map {String(format:"%.0f%% remaining",$0)} ?? "Not provided yet",detail:detail.isEmpty ? nil : detail,remaining:remaining))
            }
            if let credits = bucket["credits"] as? [String:Any] {
                let unlimited = credits["unlimited"] as? Bool == true
                let balance = string(credits["balance"])
                let amount = unlimited ? "Unlimited" : balance.map {"Remaining "+$0} ?? (credits["hasCredits"] as? Bool == false ? "No credits available" : "Balance not provided yet")
                result.rows.append(QuotaRow(title:prefix+"Available credits",value:amount,detail:unlimited ? "Credits are unlimited; other usage limits may still apply." : nil,remaining:nil))
            }
            if result.rows.count == before {
                result.rows.append(QuotaRow(title:prefix+"Usage",value:"Not provided yet",detail:"The service returned no usage windows or credit information.",remaining:nil))
            }
            if bucket["spendControlReached"] as? Bool == true {result.notice = "The workspace usage limit has been reached."}
            else if string(bucket["rateLimitReachedType"]) != nil {result.notice = "The service reports that the usage limit has been reached."}
        }
        if result.rows.isEmpty {result.rows = [QuotaRow(title:"Usage",value:"Not provided yet",detail:emptyMessage(account),remaining:nil)]}
        let cards = QuotaResetCards(value)
        result.rows.append(QuotaRow(title:"Usage reset cards",value:cards.amount,detail:cards.detail,remaining:nil))
        if value["ordinaryUsageAllowed"] as? Bool == false {result.notice = "The service is not currently allowing use of included credits."}
        return result
    }
    static func emptyMessage(_ account: [String:Any]?) -> String {
        switch account?["type"] as? String {
        case "apiKey": return "API pay-as-you-go billing; does not use ChatGPT subscription limits."
        case "amazonBedrock","gcp": return "Check billing and usage limits in the relevant cloud service."
        default: return "The service returned no usage information. This does not mean the balance is zero or unlimited."
        }
    }
    static func unavailable(account: [String:Any]?) -> QuotaOverview {
        QuotaOverview(plan:plan(nil,account:account),rows:[QuotaRow(title:"Usage",value:"Temporarily unavailable",detail:emptyMessage(account),remaining:nil)],notice:nil,management:.forAccount(account,plan:plan(nil,account:account)))
    }
}

// 参照旧 Mac 工程的鼠标四象限定位，只避让可见桌宠，不避让整块透明画布。
enum MenuPlacement {
    static func frame(size: NSSize, cursor: NSPoint, screen: NSRect, pet: NSRect) -> NSRect {
        let area = screen.insetBy(dx:8,dy:8)
        let width = min(size.width,area.width), height = min(size.height,area.height), gap = 8.0
        func clamped(_ x: CGFloat, _ top: CGFloat) -> NSRect {
            NSRect(x:max(area.minX,min(x,area.maxX-width)),y:max(area.minY,min(top-height,area.maxY-height)),width:width,height:height)
        }
        let avoid = pet.insetBy(dx:-4,dy:-4)
        let candidates = [clamped(cursor.x+gap,cursor.y-gap),clamped(cursor.x-gap-width,cursor.y-gap),
            clamped(cursor.x+gap,cursor.y+gap+height),clamped(cursor.x-gap-width,cursor.y+gap+height),
            clamped(avoid.maxX,cursor.y),clamped(avoid.minX-width,cursor.y),
            clamped(cursor.x,avoid.minY),clamped(cursor.x,avoid.maxY+height)]
        func overlap(_ r: NSRect) -> CGFloat {let i = r.intersection(avoid); return i.isNull ? 0 : i.width*i.height}
        func distance(_ r: NSRect) -> CGFloat {
            // 到菜单最近边缘的距离；左侧菜单不再因自身宽度受到惩罚。
            hypot(max(r.minX-cursor.x,0,cursor.x-r.maxX),max(r.minY-cursor.y,0,cursor.y-r.maxY))
        }
        return candidates.enumerated().min {a,b in
            let ac = overlap(a.element), bc = overlap(b.element)
            if ac != bc {return ac < bc}
            let ad = distance(a.element), bd = distance(b.element)
            return ad == bd ? a.offset < b.offset : ad < bd
        }!.element
    }
}
