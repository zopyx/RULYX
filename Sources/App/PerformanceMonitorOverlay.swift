import SwiftUI

// MARK: - PerformanceMonitorOverlay

/// A floating debug overlay showing real-time HTTP request metrics,
/// cache performance, and endpoint latency.
///
/// **Activation:** Three-finger triple-tap anywhere in the app, or Settings → Debug toggle.
///
/// **Compact mode** (default): small HUD at top of screen showing:
/// - Total request count
/// - Average latency
/// - Cache hit ratio
/// - Slowest endpoint
///
/// **Expanded mode** (tap to toggle): scrollable list of last 20 requests with full details.
struct PerformanceMonitorOverlay: View {
    @EnvironmentObject private var debugStore: HTTPRequestDebugStore
    @State private var isExpanded = false
    @State private var isVisible = false
    /// Polling timer for live updates.
    @State private var refreshTimer: Timer?
    /// Incremented on each tick to force view refresh.
    @State private var refreshTick = 0

    private let cacheMetrics: CacheMetricsProviding = BlueskyAPICache.shared

    // MARK: - Body

    var body: some View {
        Group {
            if isVisible {
                VStack(spacing: 0) {
                    compactHUD
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }

                    if isExpanded {
                        expandedDetail
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation { isVisible = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .accessibilityLabel("Close performance overlay")
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in refreshTick += 1 }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .id(refreshTick)
    }

    // MARK: - Compact HUD

    private var compactHUD: some View {
        HStack(spacing: 12) {
            metricItem(label: "Req", value: "\(requestCount)")
            metricItem(label: "Avg", value: averageLatencyString)
            metricItem(label: "Cache", value: cacheHitRatioString)
            metricItem(label: "Slow", value: slowestEndpointString)
        }
        .font(.caption2.monospacedDigit().weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func metricItem(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(minWidth: 44)
    }

    // MARK: - Expanded Detail

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            // Session summary
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session: \(requestCount) req, \(errorCount) err")
                        .font(.caption2)
                    Text("p50 \(percentile(0.50))  p95 \(percentile(0.95))  p99 \(percentile(0.99))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Cache: \(cacheHitPercent)% (\(cacheHits)/\(cacheMisses))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Endpoint breakdown
            if !endpointStats.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Endpoints").font(.caption2.weight(.semibold)).padding(.horizontal, 10)
                    ForEach(endpointStats.prefix(8), id: \.endpoint) { stat in
                        HStack {
                            Text(stat.endpoint)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text("\(stat.count)x  \(stat.averageDurationFormatted)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }

            // Last requests
            if !recentEntries.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recent").font(.caption2.weight(.semibold)).padding(.horizontal, 10)
                    ForEach(recentEntries) { entry in
                        HStack {
                            Circle()
                                .fill(entry.state == .succeeded ? Color.green : entry.state == .failed ? Color.red : Color.orange)
                                .frame(width: 5, height: 5)
                            Text(entry.method)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                            Text(shortPath(entry.url))
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            if let dur = entry.duration {
                                Text(durationString(dur))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Computed Metrics

    @MainActor
    private var completedEntries: [HTTPRequestDebugEntry] {
        debugStore.entries.filter { $0.state != .running }
    }

    @MainActor
    private var requestCount: Int {
        completedEntries.count
    }

    @MainActor
    private var errorCount: Int {
        completedEntries.filter { $0.state == .failed }.count
    }

    @MainActor
    private var slowestEndpointString: String {
        guard let slowest = endpointStats.max(by: { $0.maxDuration < $1.maxDuration }) else { return "-" }
        return durationString(slowest.maxDuration)
    }

    @MainActor
    private var averageLatencyString: String {
        let entries = completedEntries
        let durations = entries.compactMap(\.duration)
        guard !durations.isEmpty else { return "-" }
        let avg = durations.reduce(0, +) / Double(durations.count)
        return durationString(avg)
    }

    @MainActor
    private var recentEntries: [HTTPRequestDebugEntry] {
        Array(debugStore.entries.prefix(20))
    }

    @MainActor
    private var endpointStats: [EndpointLatencyStats] {
        let completed = completedEntries
        let grouped = Dictionary(grouping: completed) { entry -> String in
            extractEndpoint(entry.url)
        }
        return grouped.map { endpoint, group in
            let durations = group.compactMap(\.duration)
            guard !durations.isEmpty else {
                return EndpointLatencyStats(endpoint: endpoint, count: group.count, totalDuration: 0, maxDuration: 0, minDuration: 0)
            }
            return EndpointLatencyStats(
                endpoint: endpoint,
                count: group.count,
                totalDuration: durations.reduce(0, +),
                maxDuration: durations.max() ?? 0,
                minDuration: durations.min() ?? 0
            )
        }.sorted { $0.averageDuration > $1.averageDuration }
    }

    private var cacheHits: Int {
        cacheMetrics.hitCount
    }

    private var cacheMisses: Int {
        cacheMetrics.missCount
    }

    private var cacheHitPercent: Int {
        let total = cacheHits + cacheMisses
        guard total > 0 else { return 0 }
        return Int(Double(cacheHits) / Double(total) * 100)
    }

    private var cacheHitRatioString: String {
        "\(cacheHitPercent)%"
    }

    // MARK: - Helpers

    private func extractEndpoint(_ url: String) -> String {
        // Extract the AT Protocol lexicon path (e.g. "app.bsky.actor.getProfile")
        if let range = url.range(of: "app\\.[a-z]+\\.[a-z]+\\.[a-zA-Z]+", options: .regularExpression) {
            return String(url[range])
        }
        // Fall back to the path component
        if let pathRange = url.range(of: "(?<=://)[^/]+(/[^?]*)", options: .regularExpression) {
            return String(url[pathRange])
        }
        return url
    }

    private func shortPath(_ url: String) -> String {
        let extracted = extractEndpoint(url)
        if extracted.count > 35 {
            return String(extracted.suffix(35))
        }
        return extracted
    }

    private func durationString(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return "\(Int(interval * 1000))ms"
        }
        if interval < 60 {
            return String(format: "%.1fs", interval)
        }
        return String(format: "%.1fm", interval / 60)
    }

    @MainActor
    private func percentile(_ p: Double) -> String {
        let durations = completedEntries.compactMap(\.duration).sorted()
        guard !durations.isEmpty else { return "-" }
        let index = Int(Double(durations.count - 1) * p)
        return durationString(durations[index])
    }
}

// MARK: - EndpointLatencyStats display

private extension EndpointLatencyStats {
    var averageDurationFormatted: String {
        if averageDuration < 1 {
            return "\(Int(averageDuration * 1000))ms"
        }
        return String(format: "%.1fs", averageDuration)
    }
}
