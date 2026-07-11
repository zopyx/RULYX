import Charts
import SwiftUI

// MARK: - Stats view

/// A stats dashboard for HTTP request debugging.
///
/// Displays:
/// - Summary cards (total, succeeded, failed, error rate)
/// - Time-series bar chart (5-minute buckets, last 24 hours)
/// - Source breakdown (horizontal bar chart)
/// - CSV export via ShareLink
struct HTTPDebugStatsView: View {
    @EnvironmentObject private var debugStore: HTTPRequestDebugStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var aiService: LiveAIService
    @Environment(\.dismiss) private var dismiss

    /// Which CSV variant to share.
    @State private var exportScope: ExportScope = .full
    @State private var exportURL: URL?
    /// Selected time granularity for the timeline chart.
    @State private var granularity: HTTPDebugStatsGranularity = .fiveMinutes
    /// Selected model ID for AI analysis.
    @State private var aiModelID: String = ""
    /// Whether AI analysis is running.
    @State private var isAnalyzing = false
    /// The AI analysis result text.
    @State private var aiResult: String = ""
    /// Error from AI analysis.
    @State private var aiError: String?
    /// Available model catalog.
    @State private var catalogModels: [ModelBundle] = []

    private enum ExportScope: String, CaseIterable, Identifiable {
        case full, buckets, sources
        var id: String {
            rawValue
        }

        var localizationKey: String {
            switch self {
            case .full: "debug.http.stats.export.full"
            case .buckets: "debug.http.stats.export.buckets"
            case .sources: "debug.http.stats.export.sources"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: Summary cards

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    summaryCard(
                        title: loc("debug.http.stats.total"),
                        value: "\(debugStore.entries.count)",
                        icon: "arrow.left.arrow.right",
                        color: .primary
                    )
                    summaryCard(
                        title: loc("debug.http.stats.succeeded"),
                        value: "\(debugStore.entries.filter { $0.state == .succeeded }.count)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    summaryCard(
                        title: loc("debug.http.stats.failed"),
                        value: "\(debugStore.entries.filter { $0.state == .failed }.count)",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                    let running = debugStore.entries.filter { $0.state == .running }.count
                    summaryCard(
                        title: loc("debug.http.stats.running"),
                        value: "\(running)",
                        icon: "clock.arrow.circlepath",
                        color: running > 0 ? .orange : .secondary
                    )
                }
                .padding(.horizontal)

                // MARK: Error rate

                let totalEntries = debugStore.entries.count
                if totalEntries > 0 {
                    let failedCount = debugStore.entries.filter { $0.state == .failed }.count
                    let rate = Double(failedCount) / Double(totalEntries) * 100
                    HStack {
                        Image(systemName: rate > 10 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(rate > 10 ? .red : .green)
                        Text(String(format: "%.1f%%", rate))
                            .font(.title.weight(.bold))
                        Text(loc("debug.http.stats.error_rate"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                // MARK: Time-series chart with granularity selector

                let buckets = debugStore.statsBuckets(granularity: granularity)
                if !buckets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(loc("debug.http.stats.timeline"))
                                .font(.headline)
                            Spacer()
                            Picker("", selection: $granularity) {
                                ForEach(HTTPDebugStatsGranularity.allCases) { g in
                                    Text(loc(g.localizationKey)).tag(g)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 280)
                        }
                        .padding(.horizontal)

                        Chart {
                            ForEach(buckets) { bucket in
                                BarMark(
                                    x: .value("Time", bucket.slotStart),
                                    y: .value("Count", bucket.succeeded)
                                )
                                .foregroundStyle(by: .value("State", loc("debug.http.state.succeeded")))

                                BarMark(
                                    x: .value("Time", bucket.slotStart),
                                    y: .value("Count", bucket.failed)
                                )
                                .foregroundStyle(by: .value("State", loc("debug.http.state.failed")))
                            }
                        }
                        .chartForegroundStyleScale([
                            loc("debug.http.state.succeeded"): Color.green,
                            loc("debug.http.state.failed"): Color.red,
                        ])
                        .chartXAxis {
                            axisMarks(for: granularity)
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                                AxisGridLine()
                            }
                        }
                        .frame(height: 220)
                        .padding(.horizontal)
                    }
                }

                // MARK: Source breakdown chart

                let sources = debugStore.sourceStats
                if !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc("debug.http.stats.by_source"))
                            .font(.headline)
                            .padding(.horizontal)

                        Chart {
                            ForEach(sources.prefix(10)) { stat in
                                BarMark(
                                    x: .value("Count", stat.total),
                                    y: .value("Source", stat.source)
                                )
                                .foregroundStyle(by: .value("Source", stat.source))

                                if stat.failed > 0 {
                                    BarMark(
                                        x: .value("Count", stat.failed),
                                        y: .value("Source", stat.source)
                                    )
                                    .foregroundStyle(Color.red.opacity(0.3))
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                                AxisGridLine()
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                            }
                        }
                        .frame(height: min(CGFloat(sources.prefix(10).count) * 40, 300))
                        .padding(.horizontal)
                    }
                }

                // MARK: Source stats table

                if !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc("debug.http.stats.source_table"))
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top, 4)

                        VStack(spacing: 0) {
                            // Header row
                            HStack {
                                Text(loc("debug.http.stats.source"))
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(loc("debug.http.stats.total"))
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 50, alignment: .trailing)
                                Text("OK")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .frame(width: 40, alignment: .trailing)
                                Text("FAIL")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))

                            Divider()

                            ForEach(Array(sources.enumerated()), id: \.element.id) { _, stat in
                                HStack {
                                    Text(stat.source)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(stat.total)")
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 50, alignment: .trailing)
                                    Text("\(stat.succeeded)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.green)
                                        .frame(width: 40, alignment: .trailing)
                                    Text("\(stat.failed)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.red)
                                        .frame(width: 40, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                if stat.id != sources.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .padding(.horizontal)
                    }
                }

                // MARK: CSV Export

                VStack(spacing: 12) {
                    Text(loc("debug.http.stats.export_title"))
                        .font(.headline)

                    Picker("", selection: $exportScope) {
                        ForEach(ExportScope.allCases) { scope in
                            Text(loc(scope.localizationKey)).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    ShareLink(item: csvContent, subject: Text("HTTP Debug Export")) {
                        Label(loc("debug.http.stats.export"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)

                    Text(loc("debug.http.stats.export_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // MARK: AI Analysis

                VStack(spacing: 12) {
                    Text(loc("debug.http.ai.title"))
                        .font(.headline)

                    let generatorModels = catalogModels.filter { $0.role == .textGenerator }
                    let readyModels = generatorModels.filter { aiService.downloadStates[$0.id] == .ready }

                    if readyModels.isEmpty {
                        VStack(spacing: 6) {
                            Label(loc("debug.http.ai.no_model"), systemImage: "brain")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !generatorModels.isEmpty {
                                Text(loc("debug.http.ai.download_hint"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        if aiResult.isEmpty && !isAnalyzing {
                            Button {
                                runAIAnalysis(using: readyModels)
                            } label: {
                                Label(loc("debug.http.ai.analyze"), systemImage: "sparkle.magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isAnalyzing)
                        }

                        if isAnalyzing {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(loc("debug.http.ai.analyzing"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }

                        if !aiResult.isEmpty {
                            ScrollView {
                                Text(aiResult)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .frame(maxHeight: 250)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )

                            HStack(spacing: 12) {
                                Button(loc("debug.http.ai.analyze")) {
                                    aiResult = ""
                                    aiError = nil
                                    runAIAnalysis(using: readyModels)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isAnalyzing)

                                Button(loc("debug.http.clear"), role: .destructive) {
                                    aiResult = ""
                                    aiError = nil
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    if let error = aiError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            catalogModels = await aiService.catalog
        }
    }

    // MARK: - Axis marks for granularity

    private func axisMarks(for granularity: HTTPDebugStatsGranularity) -> some AxisContent {
        switch granularity {
        case .day:
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.weekday(.abbreviated))
                            .font(.caption2)
                    }
                }
                AxisGridLine()
            }
        case .hour:
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2)
                    }
                }
                AxisGridLine()
            }
        case .minute:
            AxisMarks(values: .stride(by: .minute, count: 15)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2)
                    }
                }
                AxisGridLine()
            }
        case .fiveMinutes:
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2)
                    }
                }
                AxisGridLine()
            }
        }
    }

    // MARK: - CSV content for ShareLink

    private var csvContent: String {
        switch exportScope {
        case .full: debugStore.csvString
        case .buckets: debugStore.csvBucketsString(granularity: granularity)
        case .sources: debugStore.csvSourceString
        }
    }

    // MARK: - Summary card

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
    // MARK: - AI Analysis

    private func runAIAnalysis(using models: [ModelBundle]) {
        guard let model = models.first else {
            aiError = loc("debug.http.ai.no_model")
            return
        }
        isAnalyzing = true
        aiResult = ""
        aiError = nil

        // Collect failed entries
        let failed = debugStore.entries.filter { $0.state == .failed }
        guard !failed.isEmpty else {
            aiResult = loc("debug.http.ai.no_failures")
            isAnalyzing = false
            return
        }

        // Format prompt
        let header = "Analyze the following failed HTTP requests and detect patterns (common status codes, error types, endpoints). Describe what's failing and suggest possible causes:\n\n"
        let rows = failed.prefix(50).map { entry in
            let time = entry.startedAt.formatted(date: .numeric, time: .shortened)
            let source = entry.source ?? "?"
            let code = entry.statusCode.map(String.init) ?? "?"
            let err = entry.errorMessage ?? "?"
            return "  [\(time)] \(source) \(entry.method) \(entry.url) → \(code) \"\(err)\""
        }.joined(separator: "\n")
        let tail = failed.count > 50 ? "\n\n... and \(failed.count - 50) more failures." : ""
        let prompt = header + rows + tail

        Task {
            var accumulated = ""
            do {
                let stream = aiService.complete(prompt: prompt, using: model.id)
                for try await token in stream {
                    accumulated += token
                    aiResult = accumulated
                }
            } catch {
                aiError = error.localizedDescription
            }
            isAnalyzing = false
        }
    }
}

#Preview {
    NavigationStack {
        HTTPDebugStatsView()
            .environmentObject(HTTPRequestDebugStore.shared)
            .environmentObject(LocalizationManager.shared)
    }
}
