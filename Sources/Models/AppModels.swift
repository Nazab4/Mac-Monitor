import Foundation

enum ChatRole: String, Sendable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: String
    let role: ChatRole
    var text: String
    let createdAt: Date
    var isStreaming: Bool

    init(
        id: String = UUID().uuidString,
        role: ChatRole,
        text: String,
        createdAt: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isStreaming = isStreaming
    }
}

enum ApprovalKind: String, Sendable {
    case commandExecution
    case fileChange
}

struct PendingApproval: Identifiable, Equatable, Sendable {
    let id: String
    let requestID: Int
    let kind: ApprovalKind
    let itemID: String
    let command: String?
    let cwd: String?
    let reason: String?

    init(
        requestID: Int,
        kind: ApprovalKind,
        itemID: String,
        command: String? = nil,
        cwd: String? = nil,
        reason: String? = nil
    ) {
        self.id = "approval-\(requestID)"
        self.requestID = requestID
        self.kind = kind
        self.itemID = itemID
        self.command = command
        self.cwd = cwd
        self.reason = reason
    }
}

struct ProcessEntry: Identifiable, Equatable, Sendable {
    var id: String { "\(pid)-\(command)" }

    let pid: Int
    let cpuPercent: String
    let memoryPercent: String
    let command: String
}

struct MacSystemSnapshot: Equatable, Sendable {
    let uptime: String
    let loadAverageOneMinute: String
    let loadAverageFiveMinutes: String
    let loadAverageFifteenMinutes: String
    let memoryUsed: String
    let memoryTotal: String
    let memoryUsedBytes: Int64
    let memoryTotalBytes: Int64
    let diskFree: String
    let diskTotal: String
    let diskFreeBytes: Int64
    let diskTotalBytes: Int64
    let swapUsed: String
    let swapTotal: String
    let swapUsedBytes: Int64
    let swapTotalBytes: Int64
    let batteryLevelPercent: Int?
    let batteryState: String?
    let processCount: Int
    let topProcesses: [ProcessEntry]
    let topMemoryProcesses: [ProcessEntry]

    static let empty = MacSystemSnapshot(
        uptime: "-",
        loadAverageOneMinute: "-",
        loadAverageFiveMinutes: "-",
        loadAverageFifteenMinutes: "-",
        memoryUsed: "-",
        memoryTotal: "-",
        memoryUsedBytes: 0,
        memoryTotalBytes: 0,
        diskFree: "-",
        diskTotal: "-",
        diskFreeBytes: 0,
        diskTotalBytes: 0,
        swapUsed: "-",
        swapTotal: "-",
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        batteryLevelPercent: nil,
        batteryState: nil,
        processCount: 0,
        topProcesses: [],
        topMemoryProcesses: []
    )

    var loadAverage: String {
        "\(loadAverageOneMinute) \(loadAverageFiveMinutes) \(loadAverageFifteenMinutes)"
    }

    var memoryUsageFraction: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(1, max(0, Double(memoryUsedBytes) / Double(memoryTotalBytes)))
    }

    var diskUsageFraction: Double {
        guard diskTotalBytes > 0 else { return 0 }
        let usedBytes = max(0, diskTotalBytes - diskFreeBytes)
        return min(1, max(0, Double(usedBytes) / Double(diskTotalBytes)))
    }

    var swapUsageFraction: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return min(1, max(0, Double(swapUsedBytes) / Double(swapTotalBytes)))
    }

    var batterySummary: String {
        guard let batteryLevelPercent else {
            return "Unavailable"
        }
        let state = batteryState ?? "Unknown"
        return "\(batteryLevelPercent)% · \(state)"
    }

    var promptSummary: String {
        let hotProcessesSummary = topProcesses
            .prefix(5)
            .map { "PID \($0.pid) CPU \($0.cpuPercent)% MEM \($0.memoryPercent)% \($0.command)" }
            .joined(separator: "\n")

        let memoryProcessesSummary = topMemoryProcesses
            .prefix(5)
            .map { "PID \($0.pid) MEM \($0.memoryPercent)% CPU \($0.cpuPercent)% \($0.command)" }
            .joined(separator: "\n")

        return """
        Mac status snapshot:
        - Uptime: \(uptime)
        - Load average (1/5/15m): \(loadAverage)
        - Memory: \(memoryUsed) / \(memoryTotal)
        - Swap: \(swapUsed) / \(swapTotal)
        - Disk free: \(diskFree) / \(diskTotal)
        - Battery: \(batterySummary)
        - Process count: \(processCount)
        - Top CPU processes:
        \(hotProcessesSummary.isEmpty ? "(no data)" : hotProcessesSummary)
        - Top memory processes:
        \(memoryProcessesSummary.isEmpty ? "(no data)" : memoryProcessesSummary)
        """
    }
}
