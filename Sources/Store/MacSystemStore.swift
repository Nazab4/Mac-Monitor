import Foundation
import Observation

@MainActor
@Observable
final class MacSystemStore {
    var snapshot: MacSystemSnapshot = .empty
    var isRefreshing = false
    var lastUpdatedAt: Date?
    var lastErrorMessage: String?

    private var didStart = false
    private var refreshTask: Task<Void, Never>?

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true

        await refreshNow()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                await self?.refreshNow()
            }
        }
    }

    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        do {
            let collected = try await Task.detached(priority: .utility) {
                try SystemCollector.collect()
            }.value

            snapshot = collected
            lastUpdatedAt = Date()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

}

private enum SystemCollector {
    static func collect() throws -> MacSystemSnapshot {
        let totalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        let availableMemoryBytes = try parseAvailableMemoryBytes(from: run(command: "vm_stat"))
        let usedMemoryBytes = max(0, Int64(totalMemoryBytes) - Int64(availableMemoryBytes))

        let loadAverage = parseLoadAverage(run(command: "sysctl -n vm.loadavg"))
        let uptime = formatUptime(ProcessInfo.processInfo.systemUptime)

        let disk = try diskCapacity()
        let swap = parseSwapUsage(run(command: "sysctl vm.swapusage"))
        let battery = parseBatteryStatus(run(command: "pmset -g batt"))
        let processCount = parseProcessCount(run(command: "ps -A | wc -l"))

        let topCPUProcesses = parseTopProcesses(
            run(command: "ps -Aceo pid,pcpu,pmem,comm | sort -k2 -nr | head -n 8")
        )
        let topMemoryProcesses = parseTopProcesses(
            run(command: "ps -Aceo pid,pcpu,pmem,comm | sort -k3 -nr | head -n 8")
        )

        return MacSystemSnapshot(
            uptime: uptime,
            loadAverageOneMinute: loadAverage.oneMinute,
            loadAverageFiveMinutes: loadAverage.fiveMinutes,
            loadAverageFifteenMinutes: loadAverage.fifteenMinutes,
            memoryUsed: formatBytes(usedMemoryBytes),
            memoryTotal: formatBytes(Int64(totalMemoryBytes)),
            memoryUsedBytes: usedMemoryBytes,
            memoryTotalBytes: Int64(totalMemoryBytes),
            diskFree: formatBytes(Int64(disk.free)),
            diskTotal: formatBytes(Int64(disk.total)),
            diskFreeBytes: Int64(disk.free),
            diskTotalBytes: Int64(disk.total),
            swapUsed: formatBytes(swap.usedBytes),
            swapTotal: formatBytes(swap.totalBytes),
            swapUsedBytes: swap.usedBytes,
            swapTotalBytes: swap.totalBytes,
            batteryLevelPercent: battery.levelPercent,
            batteryState: battery.state,
            processCount: processCount,
            topProcesses: topCPUProcesses,
            topMemoryProcesses: topMemoryProcesses
        )
    }

    private static func run(command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: output, encoding: .utf8) ?? ""
    }

    private static func parseAvailableMemoryBytes(from vmStatOutput: String) throws -> UInt64 {
        let pageSize = UInt64(parseIntMatch(pattern: "page size of ([0-9]+) bytes", in: vmStatOutput) ?? 4096)
        let freePages = UInt64(parseIntMatch(pattern: "Pages free:\\s+([0-9]+)", in: vmStatOutput) ?? 0)
        let speculativePages = UInt64(parseIntMatch(pattern: "Pages speculative:\\s+([0-9]+)", in: vmStatOutput) ?? 0)
        return (freePages + speculativePages) * pageSize
    }

    private static func parseTopProcesses(_ output: String) -> [ProcessEntry] {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .dropFirst()

        return lines.compactMap { line in
            let parts = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 4,
                  let pid = Int(parts[0])
            else {
                return nil
            }

            return ProcessEntry(
                pid: pid,
                cpuPercent: String(parts[1]),
                memoryPercent: String(parts[2]),
                command: String(parts[3])
            )
        }
    }

    private static func parseLoadAverage(_ output: String) -> (oneMinute: String, fiveMinutes: String, fifteenMinutes: String) {
        let numbers = output
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .split(whereSeparator: \.isWhitespace)
            .prefix(3)
            .map(String.init)

        let fallback = ["-", "-", "-"]
        let resolved = Array(numbers) + fallback
        return (resolved[0], resolved[1], resolved[2])
    }

    private static func formatUptime(_ seconds: TimeInterval) -> String {
        let secondsInt = max(0, Int(seconds))
        let days = secondsInt / 86_400
        let hours = (secondsInt % 86_400) / 3_600
        let minutes = (secondsInt % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private static func diskCapacity() throws -> (free: UInt64, total: UInt64) {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let values = try homeURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])

        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        return (free, total)
    }

    private static func parseSwapUsage(_ output: String) -> (usedBytes: Int64, totalBytes: Int64) {
        // Example:
        // vm.swapusage: total = 2048.00M  used = 339.50M  free = 1708.50M  (encrypted)
        let totalToken = parseRegexCapture(
            pattern: "total\\s*=\\s*([0-9.]+[KMGTP])",
            text: output
        )
        let usedToken = parseRegexCapture(
            pattern: "used\\s*=\\s*([0-9.]+[KMGTP])",
            text: output
        )

        return (
            parseByteToken(usedToken),
            parseByteToken(totalToken)
        )
    }

    private static func parseBatteryStatus(_ output: String) -> (levelPercent: Int?, state: String?) {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count > 1 else {
            return (nil, nil)
        }

        let detailLine = lines[1]
        let percent = parseIntMatch(pattern: "([0-9]+)%", in: detailLine)
        let state = parseRegexCapture(pattern: "%;\\s*([^;]+);", text: detailLine)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (percent, state)
    }

    private static func parseProcessCount(_ output: String) -> Int {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(trimmed) else {
            return 0
        }
        // Exclude header line from `ps`.
        return max(0, count - 1)
    }

    private static func parseIntMatch(pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Int(text[valueRange])
    }

    private static func parseRegexCapture(pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[valueRange])
    }

    private static func parseByteToken(_ token: String?) -> Int64 {
        guard let token else {
            return 0
        }

        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let suffix = normalized.last else {
            return 0
        }

        let multiplier: Double
        switch suffix {
        case "K":
            multiplier = 1_024
        case "M":
            multiplier = 1_048_576
        case "G":
            multiplier = 1_073_741_824
        case "T":
            multiplier = 1_099_511_627_776
        case "P":
            multiplier = 1_125_899_906_842_624
        default:
            multiplier = 1
        }

        let numberText = String(normalized.dropLast())
        guard let value = Double(numberText) else {
            return 0
        }
        return Int64(value * multiplier)
    }

    private static func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}
