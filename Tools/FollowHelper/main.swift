import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("The pet application path is missing.\n", stderr)
    exit(64)
}
FollowMonitor.run(applicationURL: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
