import Darwin
import Foundation

enum AppServerEvent: Sendable {
    case connected
    case disconnected(String)
    case threadStarted(threadID: String)
    case turnStarted(threadID: String, turnID: String)
    case turnCompleted(threadID: String, turnID: String, status: String, errorMessage: String?)
    case agentMessageDelta(threadID: String, itemID: String, delta: String)
    case agentMessageCompleted(threadID: String, itemID: String, text: String)
    case commandApprovalRequest(
        threadID: String,
        requestID: Int,
        itemID: String,
        command: String?,
        cwd: String?,
        reason: String?
    )
    case fileChangeApprovalRequest(
        threadID: String,
        requestID: Int,
        itemID: String,
        reason: String?
    )
    case toolUserInputRequest(threadID: String, requestID: Int, questionIDs: [String])
    case turnError(threadID: String?, message: String)
}

actor CodexAppServerSession {
    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func appendAndDrainLines(_ data: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }

            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                var line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.last == 0x0D {
                    line.removeLast()
                }
                if !line.isEmpty {
                    lines.append(line)
                }
            }

            return lines
        }
    }

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutLineStream: AsyncStream<Data>
    private let stdoutLineContinuation: AsyncStream<Data>.Continuation

    private let lineBuffer = LineBuffer()
    private var readerTask: Task<Void, Never>?
    private var pendingResponses: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextRequestID = 1
    private var isStarted = false
    private var isStopping = false
    private var didEmitDisconnectedEvent = false
    private var lastStderrText = ""

    private let onEvent: @Sendable (AppServerEvent) -> Void

    init(onEvent: @escaping @Sendable (AppServerEvent) -> Void) {
        var continuation: AsyncStream<Data>.Continuation!
        self.stdoutLineStream = AsyncStream<Data> { streamContinuation in
            continuation = streamContinuation
        }
        self.stdoutLineContinuation = continuation
        self.onEvent = onEvent
    }

    func start() async throws {
        guard !isStarted else {
            return
        }

        isStopping = false
        didEmitDisconnectedEvent = false
        lastStderrText = ""

        var env = ProcessInfo.processInfo.environment
        if env["PATH"] == nil {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }

        process.environment = env
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AppServerSessionError.launchFailed(error.localizedDescription)
        }

        wireOutputReaders()
        startReaderLoop()

        do {
            _ = try await sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "mac-monitor",
                        "title": "MacMonitor",
                        "version": "0.1.0",
                    ],
                    "capabilities": [
                        "experimentalApi": false,
                    ],
                ]
            )
            try sendNotification(method: "initialized", params: [:])
        } catch {
            await stop()
            throw error
        }

        isStarted = true
        onEvent(.connected)
    }

    func startThread(cwd: String, developerInstructions: String?) async throws -> String {
        var params: [String: Any] = [
            "cwd": cwd,
            "serviceName": "mac-monitor",
            "personality": "pragmatic",
        ]

        if let developerInstructions, !developerInstructions.isEmpty {
            params["developerInstructions"] = developerInstructions
        }

        let message = try await sendRequest(method: "thread/start", params: params)
        return try extractThreadID(from: message)
    }

    func resumeThread(threadID: String) async throws {
        _ = try await sendRequest(
            method: "thread/resume",
            params: ["threadId": threadID]
        )
    }

    func startTurn(threadID: String, text: String) async throws {
        _ = try await sendRequest(
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [
                    [
                        "type": "text",
                        "text": text,
                        "textElements": [] as [String],
                    ],
                ],
            ]
        )
    }

    func respondToCommandApproval(requestID: Int, accept: Bool) throws {
        try sendResponse(
            id: requestID,
            result: ["decision": accept ? "accept" : "decline"]
        )
    }

    func respondToFileChangeApproval(requestID: Int, accept: Bool) throws {
        try sendResponse(
            id: requestID,
            result: ["decision": accept ? "accept" : "decline"]
        )
    }

    func respondToToolUserInput(requestID: Int, answersByQuestionID: [String: String]) throws {
        var answers: [String: Any] = [:]
        for (questionID, answer) in answersByQuestionID {
            answers[questionID] = ["answers": [answer]]
        }
        try sendResponse(id: requestID, result: ["answers": answers])
    }

    func stop() async {
        isStopping = true
        readerTask?.cancel()
        readerTask = nil

        if process.isRunning {
            process.terminate()
            var didExit = await waitUntilExit(process, timeoutNanoseconds: 2_000_000_000)
            if !didExit, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                didExit = await waitUntilExit(process, timeoutNanoseconds: 1_000_000_000)
            }
            _ = didExit
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutLineContinuation.finish()

        resolveAllPendingResponses(with: AppServerSessionError.closed)
        emitDisconnected(message: !lastStderrText.isEmpty ? lastStderrText : "Codex app-server stopped.")
        isStarted = false
    }

    private func wireOutputReaders() {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [lineBuffer, stdoutLineContinuation] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stdoutLineContinuation.finish()
                return
            }

            for line in lineBuffer.appendAndDrainLines(data) {
                stdoutLineContinuation.yield(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }

            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return
            }

            Task {
                await self?.appendStderr(text)
            }
        }
    }

    private func appendStderr(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if lastStderrText.isEmpty {
            lastStderrText = trimmed
        } else {
            lastStderrText += "\n\(trimmed)"
        }
    }

    private func startReaderLoop() {
        readerTask = Task { [weak self] in
            guard let self else { return }

            for await lineData in self.stdoutLineStream {
                await self.processIncomingLine(lineData)
            }

            await self.handleReaderLoopEnded()
        }
    }

    private func processIncomingLine(_ lineData: Data) {
        guard let payload = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return
        }

        let requestID = Self.jsonInt(payload["id"])
        let method = payload["method"] as? String

        if let requestID, method == nil {
            // Response to a client request.
            if let continuation = pendingResponses.removeValue(forKey: requestID) {
                if let errorObject = payload["error"] as? [String: Any] {
                    let message = errorObject["message"] as? String ?? "Unknown app-server error"
                    continuation.resume(throwing: AppServerSessionError.rpcError(message))
                } else {
                    continuation.resume(returning: payload)
                }
            }
            return
        }

        if let requestID, let method {
            // Server-initiated request requiring a response.
            handleServerRequest(id: requestID, method: method, params: payload["params"] as? [String: Any] ?? [:])
            return
        }

        if let method {
            // Notification.
            handleNotification(method: method, params: payload["params"] as? [String: Any] ?? [:])
        }
    }

    private func handleServerRequest(id requestID: Int, method: String, params: [String: Any]) {
        switch method {
        case "item/commandExecution/requestApproval":
            guard let threadID = resolveThreadID(params: params) else {
                return
            }
            let itemID = Self.nonEmptyString(params["itemId"] ?? params["item_id"]) ?? "unknown"
            let command = params["command"] as? String
            let cwd = params["cwd"] as? String
            let reason = params["reason"] as? String
            onEvent(
                .commandApprovalRequest(
                    threadID: threadID,
                    requestID: requestID,
                    itemID: itemID,
                    command: command,
                    cwd: cwd,
                    reason: reason
                )
            )

        case "item/fileChange/requestApproval":
            guard let threadID = resolveThreadID(params: params) else {
                return
            }
            let itemID = Self.nonEmptyString(params["itemId"] ?? params["item_id"]) ?? "unknown"
            let reason = params["reason"] as? String
            onEvent(
                .fileChangeApprovalRequest(
                    threadID: threadID,
                    requestID: requestID,
                    itemID: itemID,
                    reason: reason
                )
            )

        case "item/tool/requestUserInput":
            guard let threadID = resolveThreadID(params: params) else {
                return
            }
            let questionIDs: [String]
            if let questions = params["questions"] as? [[String: Any]] {
                questionIDs = questions.compactMap { Self.nonEmptyString($0["id"]) }
            } else {
                questionIDs = []
            }
            onEvent(.toolUserInputRequest(threadID: threadID, requestID: requestID, questionIDs: questionIDs))

        default:
            do {
                try sendResponse(id: requestID, result: [:])
            } catch {
                onEvent(.turnError(threadID: nil, message: "Failed to answer server request \(method): \(error.localizedDescription)"))
            }
        }
    }

    private func handleNotification(method: String, params: [String: Any]) {
        switch method {
        case "thread/started":
            guard let thread = params["thread"] as? [String: Any],
                  let threadID = Self.nonEmptyString(thread["id"])
            else {
                return
            }
            onEvent(.threadStarted(threadID: threadID))

        case "turn/started":
            guard let turn = params["turn"] as? [String: Any],
                  let turnID = Self.nonEmptyString(turn["id"])
            else {
                return
            }
            guard let threadID = resolveThreadID(params: params, turn: turn) else {
                return
            }
            onEvent(.turnStarted(threadID: threadID, turnID: turnID))

        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any],
                  let turnID = Self.nonEmptyString(turn["id"])
            else {
                return
            }

            let status = turn["status"] as? String ?? "unknown"
            let errorMessage: String?
            if let turnError = turn["error"] as? [String: Any] {
                errorMessage = turnError["message"] as? String
            } else {
                errorMessage = nil
            }

            guard let threadID = resolveThreadID(params: params, turn: turn) else {
                return
            }
            onEvent(.turnCompleted(threadID: threadID, turnID: turnID, status: status, errorMessage: errorMessage))

        case "item/agentMessage/delta":
            guard let itemID = Self.nonEmptyString(params["itemId"] ?? params["item_id"]),
                  let delta = Self.rawString(params["delta"]),
                  let threadID = resolveThreadID(params: params)
            else {
                return
            }
            onEvent(.agentMessageDelta(threadID: threadID, itemID: itemID, delta: delta))

        case "item/completed":
            guard let item = params["item"] as? [String: Any],
                  let type = item["type"] as? String,
                  type == "agentMessage",
                  let itemID = Self.nonEmptyString(item["id"]),
                  let text = Self.rawString(item["text"]),
                  let threadID = resolveThreadID(params: params, item: item)
            else {
                return
            }
            onEvent(.agentMessageCompleted(threadID: threadID, itemID: itemID, text: text))

        case "error":
            if let errorObject = params["error"] as? [String: Any],
               let message = Self.rawString(errorObject["message"]) {
                onEvent(.turnError(threadID: resolveThreadID(params: params), message: message))
            }

        case "thread/closed":
            emitDisconnected(message: "Thread closed by app-server.")

        default:
            break
        }
    }

    private func handleReaderLoopEnded() {
        resolveAllPendingResponses(with: AppServerSessionError.closed)
        if !isStopping {
            emitDisconnected(
                message: !lastStderrText.isEmpty
                    ? lastStderrText
                    : "Lost connection to codex app-server."
            )
        }
        isStarted = false
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try sendPayload(["method": method, "params": params])
    }

    private func sendResponse(id: Int, result: [String: Any]) throws {
        try sendPayload(["id": id, "result": result])
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextRequestID
        nextRequestID += 1

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation

            do {
                try sendPayload(["id": id, "method": method, "params": params])
            } catch {
                pendingResponses.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendPayload(_ payload: [String: Any]) throws {
        guard process.isRunning else {
            throw AppServerSessionError.closed
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data([0x0A]))
    }

    private func resolveAllPendingResponses(with error: Error) {
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func extractThreadID(from response: [String: Any]) throws -> String {
        guard let result = response["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any],
              let threadID = Self.nonEmptyString(thread["id"])
        else {
            throw AppServerSessionError.malformedResponse("Missing thread id in thread/start response")
        }

        return threadID
    }

    private func resolveThreadID(
        params: [String: Any],
        turn: [String: Any]? = nil,
        item: [String: Any]? = nil
    ) -> String? {
        if let threadID = Self.nonEmptyString(params["threadId"] ?? params["thread_id"]) {
            return threadID
        }

        if let turn, let threadID = Self.nonEmptyString(turn["threadId"] ?? turn["thread_id"]) {
            return threadID
        }

        if let item, let threadID = Self.nonEmptyString(item["threadId"] ?? item["thread_id"]) {
            return threadID
        }

        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func rawString(_ value: Any?) -> String? {
        value as? String
    }

    private func emitDisconnected(message: String) {
        guard !didEmitDisconnectedEvent else {
            return
        }
        didEmitDisconnectedEvent = true
        onEvent(.disconnected(message))
    }

    private func waitUntilExit(_ process: Process, timeoutNanoseconds: UInt64) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        process.waitUntilExit()
                        continuation.resume(returning: ())
                    }
                }
                return true
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return false
                }
                return false
            }

            let didExit = await group.next() ?? false
            group.cancelAll()
            return didExit
        }
    }

    private static func jsonInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let stringValue = value as? String {
            return Int(stringValue)
        }

        return nil
    }
}

enum AppServerSessionError: LocalizedError {
    case launchFailed(String)
    case malformedResponse(String)
    case rpcError(String)
    case closed

    var errorDescription: String? {
        switch self {
        case .launchFailed(let detail):
            return "Failed to launch codex app-server: \(detail)"
        case .malformedResponse(let detail):
            return "Malformed app-server response: \(detail)"
        case .rpcError(let message):
            return "Codex app-server error: \(message)"
        case .closed:
            return "Connection to codex app-server was closed."
        }
    }
}
