import AppKit

enum MessageSettingsPage {
    static func render(form:SettingsForm,onPreview:@escaping (MessagePurpose) -> Void) {
        form.group("History",[form.toggle("Save history","recordHistory",detail:"Stops adding or updating local history while retaining existing records. Current task context stays in memory (RAM). Re-enabling does not backfill this period. Original Codex history is unaffected.")])
        form.group("In-bubble approvals",[form.choice("Approval button order","approvalButtonOrder",[("rejectLeft","Deny left · Allow right"),("allowLeft","Allow left · Deny right")],detail:"Changes only the approval button order in pet bubbles, not native approval dialogs or Codex. A red cross means deny; a green check means allow. Keyboard keys do not approve requests.")])
        form.group("Input shortcut",[
            form.choice("Sending & new lines","sendShortcut",SendShortcut.options),
            form.note(SendShortcut.settingsExplanation)])
        form.group("Task bubbles",[
            form.toggle("Show task bubbles","taskBubbles",detail:"Controls task messages, final replies, and thinking/tool progress pop-ups. Approvals, input requests, and failures remain visible."),
            form.toggle("Task messages","progressBubbles",detail:"Show assistant messages while a task runs.",requires:["taskBubbles"]),
            form.toggle("Final replies","resultBubbles",requires:["taskBubbles"]),
            form.toggle("Thinking & tool progress pop-ups","progressToastEnabled",detail:"When task messages are enabled, changes to thinking summaries or tool status show a brief pop-up.",requires:["taskBubbles","progressBubbles"])])
        form.group("Progress reminders",[
            form.toggle("Remind me when progress stalls","taskReminderEnabled",detail:"Show a reminder after 90 seconds without progress and once the reminder interval has elapsed. No reminders while waiting for input, approval, or stopping.",requires:["taskBubbles","progressBubbles"]),
            form.slider("Reminder interval","taskReminderMinutes",range:1...30,suffix:"minutes",requires:["taskBubbles","progressBubbles","taskReminderEnabled"])])
        form.group("Message types",[
            form.toggle("Interaction lines","interactionBubbles"),
            form.toggle("Show thinking summaries","showThinkingProgress",detail:"Show public thinking summaries in task overview and progress pop-ups, without adding message cards."),
            form.toggle("Show tool calls","showToolProgress",detail:"Show tool names, operations, and status in task overview and progress pop-ups, without adding message cards.")])
        form.group("Message cards & task overview",[
            form.slider("Message cards to keep","bubbleCardLimit",range:5...100,suffix:"items"),
            form.toggle("Show task overview with interactions","showTaskOverview",detail:"The task-progress mouse action lists current and recent tasks below the dialogue. Click a task to open it in Codex."),
            form.slider("Recent completed tasks","recentTaskCount",range:1...20,suffix:"items",detail:"Show the latest turn from each chat.",requires:["showTaskOverview"])])
        form.group("Display duration",[
            form.slider("Interaction lines","interactionSeconds",range:0...60,suffix:"seconds",requires:["interactionBubbles"]),
            form.slider("Task messages","progressSeconds",range:0...60,suffix:"seconds",requires:["taskBubbles","progressBubbles"]),
            form.slider("Final replies","resultSeconds",range:0...120,suffix:"seconds",requires:["taskBubbles","resultBubbles"]),
            form.slider("Usage information","quotaSeconds",range:0...120,suffix:"seconds"),
            form.note("Set to 0 for manual closing. Approvals, input requests, and failures stay until handled or closed manually."),
            form.toggle("Allow more reading time for long replies","autoReadTime",detail:"Extend up to 120 seconds. Manual-close mode is unaffected.",requires:["taskBubbles","resultBubbles"]),
            form.toggle("Pause countdown on hover","pauseOnHover"),
            form.slider("Thinking & tool progress pop-ups","progressToastSeconds",range:1...10,suffix:"seconds",detail:"Default: 2 seconds. Restarts when the content changes.",requires:["taskBubbles","progressBubbles","progressToastEnabled"]),
            form.row("Preview final reply bubble",control:ActionButton("Preview…") {onPreview(.result)})])
        form.group("Sound",[form.toggle("Play sound effects","soundEnabled")])
        form.group("Quiet companionship",[
            form.toggle("Enable quiet companionship now","quietCompanion",detail:"Reduce activity, stop autonomous movement, and turn off interaction lines, progress bubbles, and sounds. Final replies and pending requests remain visible."),
            form.toggle("Schedule quiet companionship","quietSchedule",detail:"Enable now keeps the pet quiet continuously. Turn it off to use the schedule."),
            form.time("Start time","quietStart",requires:["quietSchedule"]),
            form.time("End time","quietEnd",requires:["quietSchedule"]),
            form.note("Uses local time and supports overnight schedules. Equal start and end times mean all day.")])
    }
}
