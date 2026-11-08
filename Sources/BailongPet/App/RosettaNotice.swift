import AppKit
import Darwin

enum RosettaNotice {
    // 只提示已经通过 Rosetta 启动的 Intel 主程序；原生运行及跟随助手不弹窗。
    static func confirmLaunch() -> Bool {
        #if arch(x86_64)
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 else {
            let code = errno
            // Intel Mac 没有这个键；其他查询错误保留实际诊断，不据此宣称架构。
            if code != ENOENT {
                NSLog("Unable to detect Rosetta translation: %@", NSError(domain:NSPOSIXErrorDomain,code:Int(code)).localizedDescription)
            }
            return true
        }
        guard translated == 1 else {return true}

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Use the Apple Silicon version on this Mac"
        alert.informativeText = "The Intel version is running through Rosetta. Use the native Apple Silicon version instead.\n\nDownload the package ending in macos-apple-silicon.zip from the releases page."
        alert.addButton(withTitle:"Download and Quit")
        alert.addButton(withTitle:"Run Intel Version Anyway")
        alert.addButton(withTitle:"Quit").keyEquivalent = "\u{1b}"
        alert.applyAccent()
        NSApp.activate(ignoringOtherApps:true)
        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let url = UpdateChecker.releases.appendingPathComponent("latest")
                if NSWorkspace.shared.open(url) {return false}
                showError("Unable to open releases page",PetFailure(message:url.absoluteString))
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
        #else
        return true
        #endif
    }
}
