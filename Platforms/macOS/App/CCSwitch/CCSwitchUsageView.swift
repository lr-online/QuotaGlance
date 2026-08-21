import QuotaGlanceCore
import SwiftUI

struct CCSwitchUsageView: View {
    let language: AppLanguage
    @StateObject private var model = CCSwitchUsageViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if model.databaseURL == nil {
                    databaseEmptyState
                } else if let dashboard = model.dashboard {
                    dashboardContent(dashboard)
                } else if model.isLoading {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    databaseEmptyState
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.start() }
        .onChange(of: model.range) { _ in model.refresh() }
        .onChange(of: model.selectedApp) { _ in model.refresh() }
        .task(id: model.databaseURL?.path) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                model.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(.ccSwitchUsage, language: language))
                    .font(.title2.weight(.semibold))
                Text(L10n.string(.ccSwitchUsageSubtitle, language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Range", selection: $model.range) {
                ForEach(CCSwitchTimeRange.standardRanges) { range in
                    Text(range.label).tag(range)
                }
            }
            .labelsHidden()
            .frame(width: 88)
            Picker("App", selection: $model.selectedApp) {
                Text(L10n.string(.allAccounts, language: language)).tag(nil as String?)
                ForEach(model.dashboard?.knownApps ?? [], id: \.self) { app in
                    Text(app).tag(app as String?)
                }
            }
            .labelsHidden()
            .frame(width: 118)
            if model.isLoading {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(L10n.string(.refresh, language: language))
            }
            Button { model.selectDatabase() } label: {
                Image(systemName: "externaldrive.badge.plus").frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(model.isSelectingDatabase)
            .help(L10n.string(.changeDatabase, language: language))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var databaseEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(L10n.string(.databaseNotSelected, language: language))
                .font(.title3.weight(.semibold))
            Text(L10n.string(.databaseSelectionHint, language: language))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                model.selectDatabase()
            } label: {
                if model.isSelectingDatabase {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L10n.string(.chooseDatabase, language: language), systemImage: "folder")
                }
            }
            .disabled(model.isSelectingDatabase)
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 480)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func dashboardContent(_ dashboard: CCSwitchUsageDashboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                summaryTiles(dashboard.summary, range: dashboard.range)
                usageChart(dashboard)
                HStack(alignment: .top, spacing: 24) {
                    breakdownSection(
                        L10n.string(.applications, language: language),
                        rows: dashboard.applications
                    )
                    breakdownSection(
                        L10n.string(.providers, language: language),
                        rows: dashboard.providers
                    )
                }
                breakdownSection(
                    L10n.string(.topModels, language: language),
                    rows: dashboard.models,
                    showsDetail: false
                )
                if !dashboard.failures.isEmpty { failureSection(dashboard.failures) }
                recentRequests(dashboard.recentRequests)
            }
            .padding(24)
            .frame(maxWidth: 1_140, alignment: .leading)
        }
    }

    private func summaryTiles(_ summary: CCSwitchUsageSummary, range: CCSwitchTimeRange) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: 4),
            spacing: 12
        ) {
            metricTile(L10n.string(.requests, language: language), summary.requests.formatted(), accent: .blue)
            metricTile(L10n.string(.totalTokens, language: language), compactNumber(summary.totalTokens), accent: .indigo)
            metricTile(L10n.string(.tokenRate, language: language), tokenRate(summary.totalTokens, range: range), accent: .teal)
            metricTile("USD", money(summary.costUSD), accent: .green)
            metricTile(L10n.string(.medianLatency, language: language), milliseconds(summary.medianLatencyMilliseconds), accent: .orange)
            metricTile(L10n.string(.timeToFirstToken, language: language), milliseconds(summary.averageFirstTokenMilliseconds), accent: .purple)
            metricTile(L10n.string(.failureRate, language: language), summary.failureRate.formatted(.percent.precision(.fractionLength(1))), accent: summary.failedRequests == 0 ? .green : .red)
        }
    }

    private func metricTile(_ title: String, _ value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func usageChart(_ dashboard: CCSwitchUsageDashboard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string(.tokenActivity, language: language))
                        .font(.title3.weight(.semibold))
                    Text("\(dashboard.range.label) · \(dashboard.summary.requests.formatted()) \(L10n.string(.requests, language: language).lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let capturedAt = Optional(dashboard.capturedAt) {
                    Text(capturedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }
            if dashboard.timeline.isEmpty {
                Text(L10n.string(.noRequestsInRange, language: language))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                CCSwitchTokenChart(points: dashboard.timeline)
                    .frame(height: 180)
            }
        }
    }

    private func breakdownSection(
        _ title: String,
        rows: [CCSwitchBreakdownRow],
        showsDetail: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            if rows.isEmpty {
                Text(L10n.string(.noData, language: language)).font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(8).enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.name).font(.body.weight(.medium)).lineLimit(1)
                                if showsDetail, let detail = row.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                } else {
                                    Text("\(row.requests.formatted()) \(L10n.string(.requests, language: language).lowercased())")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 12)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(compactNumber(row.tokens)).font(.body.monospacedDigit().weight(.medium))
                                HStack(spacing: 5) {
                                    if row.failures > 0 { Text("\(row.failures) failed").foregroundStyle(.red) }
                                    if row.costUSD > 0 { Text(money(row.costUSD)) }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureSection(_ failures: [CCSwitchFailure]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("HTTP failures", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold)).foregroundStyle(.red)
            ForEach(failures) { failure in
                HStack {
                    Text("HTTP \(failure.statusCode)").fontWeight(.medium)
                    Text("\(failure.count.formatted()) requests").foregroundStyle(.secondary)
                    Spacer()
                    if let sample = failure.sampleMessage { Text(sample).foregroundStyle(.secondary).lineLimit(1) }
                }
                .font(.callout)
            }
        }
    }

    private func recentRequests(_ requests: [CCSwitchRecentRequest]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(.recentRequests, language: language)).font(.title3.weight(.semibold))
            if requests.isEmpty {
                Text(L10n.string(.noData, language: language)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                        if index > 0 { Divider() }
                        HStack(spacing: 12) {
                            Text(request.createdAt, style: .time).frame(width: 66, alignment: .leading).foregroundStyle(.secondary)
                            Text(request.app).frame(width: 62, alignment: .leading).lineLimit(1)
                            Text(request.provider).frame(width: 100, alignment: .leading).lineLimit(1)
                            Text(request.model).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(compactNumber(request.outputTokens)).font(.body.monospacedDigit())
                            Text(milliseconds(request.latencyMilliseconds)).frame(width: 58, alignment: .trailing).foregroundStyle(.secondary)
                            Text("\(request.statusCode)").font(.caption.monospacedDigit()).foregroundStyle(request.statusCode < 300 ? .green : .red).frame(width: 30, alignment: .trailing)
                        }
                        .font(.callout)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func compactNumber(_ value: Int64) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
    }

    private func tokenRate(_ tokens: Int64, range: CCSwitchTimeRange) -> String {
        let perSecond = Double(tokens) / max(range.seconds, 1)
        return "\(perSecond.formatted(.number.notation(.compactName).precision(.significantDigits(3)))) token/s"
    }

    private func money(_ value: Decimal) -> String { "$\(value.formatted(.number.precision(.fractionLength(0...4))))" }
    private func milliseconds(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value >= 1_000 ? "\((value / 1_000).formatted(.number.precision(.fractionLength(1))))s" : "\(value.formatted(.number.precision(.fractionLength(0))))ms"
    }
}

private struct CCSwitchTokenChart: View {
    let points: [CCSwitchTimelinePoint]

    private var maximum: Double { max(points.map { Double($0.totalTokens) }.max() ?? 0, 1) }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: max(3, proxy.size.width / CGFloat(max(points.count, 1)) * 0.18)) {
                ForEach(points) { point in
                    let fraction = Double(point.totalTokens) / maximum
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(point.requestCount == 0 ? 0.25 : 0.88))
                            .frame(height: max(3, (proxy.size.height - 22) * fraction))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        Text(point.startedAt, format: .dateTime.hour().minute())
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(point.totalTokens.formatted()) tokens · \(point.requestCount.formatted()) requests")
                }
            }
        }
        .accessibilityLabel("Token activity")
    }
}
