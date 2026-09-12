import OSLog

enum AppLogger {
    static let auth = Logger(subsystem: "cx.loe.LoeBalance", category: "auth")
    static let api = Logger(subsystem: "cx.loe.LoeBalance", category: "api")
    static let refresh = Logger(subsystem: "cx.loe.LoeBalance", category: "refresh")
    static let desktop = Logger(subsystem: "cx.loe.LoeBalance", category: "desktop")
    static let status = Logger(subsystem: "cx.loe.LoeBalance", category: "status")
}
