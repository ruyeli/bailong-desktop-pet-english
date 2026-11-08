import Foundation

enum TaskOutcome {
    /// 会话标题来自用户，禁止将它回填为助手的结果正文。
    static func body(status: String, error: String, final: String) -> String {
        let raw = error.trimmingCharacters(in:.whitespacesAndNewlines)
        if !raw.isEmpty, raw != "null" {
            if let json = try? JSONSerialization.jsonObject(with:Data(raw.utf8),options:.fragmentsAllowed) {
                let message = (json as? [String:Any])?["message"] as? String ?? json as? String
                if let message, !message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return message}
            } else {return raw}
        }
        if !final.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return final}
        switch status {
        case "completed": return "The task completed. Codex did not provide a text reply."
        case "interrupted": return "The task was interrupted. No final reply was received."
        default: return "The task failed. Codex did not provide an error description."
        }
    }
}
