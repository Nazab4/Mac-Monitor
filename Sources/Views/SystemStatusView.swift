import SwiftUI
import Observation

struct SystemStatusView: View {
    @Bindable var conversationStore: ConversationStore
    @Bindable var systemStore: MacSystemStore
    let onSendToAgent: () -> Void

    private let metricColumns = [
        GridItem(.flexible(minimum: 140), spacing: 10),
        GridItem(.flexible(minimum: 140), spacing: 10)
    ]
    private let statusColumns = [
        GridItem(.flexible(minimum: 90), spacing: 10),
        GridItem(.flexible(minimum: 90), spacing: 10),
        GridItem(.flexible(minimum: 90), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 9) {
                systemPanelContent
                    .padding(.vertical, 1)
            }
        }
    }

    private var systemPanelContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerCard

            if let error = systemStore.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 2)
            }

            metricsGrid
            quickActionsCard
            processSection(
                title: "Top CPU Processes",
                subtitle: "Sorted by CPU usage",
                processes: systemStore.snapshot.topProcesses,
                askPrompt: { process in
                    "Why is process \(process.command) (PID \(process.pid)) using \(process.cpuPercent)% CPU, and what safe actions should I take?"
                }
            )
            processSection(
                title: "Top Memory Processes",
                subtitle: "Sorted by memory usage",
                processes: systemStore.snapshot.topMemoryProcesses,
                askPrompt: { process in
                    "Process \(process.command) (PID \(process.pid)) is using \(process.memoryPercent)% memory. Is this expected, and what should I check first?"
                }
            )
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac Overview")
                        .font(.headline)

                    Text("Live machine state + fast questions for the agent")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastUpdatedAt = systemStore.lastUpdatedAt {
                        Text("Updated \(lastUpdatedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 10)

                HStack(spacing: 6) {
                    Button {
                        Task {
                            await systemStore.refreshNow()
                        }
                    } label: {
                        if systemStore.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.glass)

                    Button {
                        Task {
                            onSendToAgent()
                            await conversationStore.sendSystemSnapshot(systemStore.snapshot)
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .controlSize(.small)
                    .buttonStyle(.glass)
                    .disabled(!conversationStore.canSendQuickAction)
                }
            }

            Divider()

            LazyVGrid(columns: statusColumns, spacing: 10) {
                statusChip(
                    title: "Battery",
                    value: systemStore.snapshot.batterySummary,
                    color: .green
                )

                statusChip(
                    title: "Processes",
                    value: "\(systemStore.snapshot.processCount)",
                    color: .blue
                )

                statusChip(
                    title: "Uptime",
                    value: systemStore.snapshot.uptime,
                    color: .orange
                )
            }
        }
        .padding(10)
        .glassCardSurface(cornerRadius: 12)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: metricColumns, spacing: 8) {
            metricTile(
                title: "Load Avg (1 / 5 / 15)",
                value: systemStore.snapshot.loadAverage,
                subtitle: "CPU pressure trend",
                tint: .purple
            )

            metricTile(
                title: "Memory",
                value: "\(systemStore.snapshot.memoryUsed) / \(systemStore.snapshot.memoryTotal)",
                subtitle: percentText(systemStore.snapshot.memoryUsageFraction),
                tint: .mint,
                progress: systemStore.snapshot.memoryUsageFraction
            )

            metricTile(
                title: "Disk",
                value: "\(systemStore.snapshot.diskFree) free",
                subtitle: "Total \(systemStore.snapshot.diskTotal)",
                tint: .teal,
                progress: systemStore.snapshot.diskUsageFraction
            )

            metricTile(
                title: "Swap",
                value: "\(systemStore.snapshot.swapUsed) / \(systemStore.snapshot.swapTotal)",
                subtitle: percentText(systemStore.snapshot.swapUsageFraction),
                tint: .indigo,
                progress: systemStore.snapshot.swapUsageFraction
            )
        }
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quick Actions")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("Send a targeted question to the agent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: metricColumns, spacing: 7) {
                ForEach(quickActions) { action in
                    Button {
                        Task {
                            onSendToAgent()
                            await conversationStore.sendQuickQuestion(action.prompt, snapshot: systemStore.snapshot)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.symbol)
                                .foregroundStyle(action.tint)
                                .frame(width: 16)
                            Text(action.title)
                                .multilineTextAlignment(.leading)
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 54, alignment: .leading)
                        .glassCardSurface(cornerRadius: 10, tint: action.tint, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(!conversationStore.canSendQuickAction)
                }
            }
        }
        .padding(10)
        .glassCardSurface(cornerRadius: 12)
    }

    private func processSection(
        title: String,
        subtitle: String,
        processes: [ProcessEntry],
        askPrompt: @escaping (ProcessEntry) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if processes.isEmpty {
                Text("No process data available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(processes.prefix(7)) { process in
                        HStack(spacing: 8) {
                            Text("PID \(process.pid)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 86, alignment: .leading)

                            Text("CPU \(process.cpuPercent)%")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 94, alignment: .leading)

                            Text("MEM \(process.memoryPercent)%")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 98, alignment: .leading)

                            Text(process.command)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Button("Ask") {
                                Task {
                                    onSendToAgent()
                                    await conversationStore.sendQuickQuestion(askPrompt(process), snapshot: systemStore.snapshot)
                                }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .buttonStyle(.glass)
                            .disabled(!conversationStore.canSendQuickAction)
                        }
                    }
                }
            }
        }
        .padding(10)
        .glassCardSurface(cornerRadius: 12)
    }

    private var quickActions: [QuickAction] {
        var actions: [QuickAction] = [
            QuickAction(
                title: "Analyze Overall Health",
                prompt: "Analyze current system health and highlight the top 3 concerns with priorities.",
                symbol: "stethoscope",
                tint: .blue
            ),
            QuickAction(
                title: "Reduce Memory Pressure",
                prompt: "Give me a safe, step-by-step plan to reduce memory pressure right now.",
                symbol: "memorychip",
                tint: .mint
            ),
            QuickAction(
                title: "Check Disk Cleanup",
                prompt: "Suggest quick and safe disk cleanup actions based on current disk usage.",
                symbol: "externaldrive.badge.exclamationmark",
                tint: .orange
            ),
            QuickAction(
                title: "Performance Triage",
                prompt: "Triage system performance with likely bottlenecks from this snapshot.",
                symbol: "gauge.with.dots.needle.67percent",
                tint: .purple
            )
        ]

        if let topCPU = systemStore.snapshot.topProcesses.first {
            actions.append(
                QuickAction(
                    title: "Investigate \(shortProcessName(topCPU.command))",
                    prompt: "Investigate process \(topCPU.command) (PID \(topCPU.pid)) high CPU usage and recommend safe next actions.",
                    symbol: "cpu",
                    tint: .teal
                )
            )
        }

        if let topMemory = systemStore.snapshot.topMemoryProcesses.first {
            actions.append(
                QuickAction(
                    title: "Review \(shortProcessName(topMemory.command))",
                    prompt: "Review memory behavior for process \(topMemory.command) (PID \(topMemory.pid)) and suggest whether action is needed.",
                    symbol: "chart.bar.doc.horizontal",
                    tint: .indigo
                )
            )
        }

        return actions
    }

    private func shortProcessName(_ command: String) -> String {
        let url = URL(fileURLWithPath: command)
        let name = url.lastPathComponent
        return name.isEmpty ? command : name
    }

    private func percentText(_ fraction: Double) -> String {
        let value = Int((fraction * 100).rounded())
        return "\(value)% used"
    }

    private func statusChip(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .glassCardSurface(cornerRadius: 10, tint: color)
    }

    private func metricTile(
        title: String,
        value: String,
        subtitle: String,
        tint: Color,
        progress: Double? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
            } else {
                ProgressView(value: 0)
                    .progressViewStyle(.linear)
                    .tint(.clear)
                    .hidden()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 104, alignment: .topLeading)
        .glassCardSurface(cornerRadius: 10, tint: tint)
    }
}

private struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let prompt: String
    let symbol: String
    let tint: Color
}

private extension View {
    func glassCardSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        if let tint {
            if interactive {
                return self.glassEffect(.regular.tint(tint.opacity(0.14)).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                return self.glassEffect(.regular.tint(tint.opacity(0.14)), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            if interactive {
                return self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                return self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        }
    }
}
