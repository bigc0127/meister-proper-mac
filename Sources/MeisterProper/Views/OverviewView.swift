import SwiftUI

struct OverviewView: View {
    @State private var snap = StatusSnapshot()
    @State private var loading = true
    @State private var lastRefresh = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if loading {
                    ProgressView("Reading system status…").controlSize(.large)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    grid
                    healthCard
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem {
                Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .task { await refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snap.host).font(.system(.title, design: .rounded).bold())
                Text("\(snap.modelName) · \(snap.osVersion) · up \(snap.uptime)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Updated \(lastRefresh.formatted(date: .omitted, time: .standard))")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            metric("CPU usage", value: String(format: "%.0f%%", snap.cpuUsage), icon: "cpu", tint: barColor(snap.cpuUsage / 100))
            metric("Memory",
                   value: String(format: "%.1f / %.1f GB", snap.memUsedGB, snap.memTotalGB),
                   icon: "memorychip",
                   tint: barColor(snap.memTotalGB > 0 ? snap.memUsedGB / snap.memTotalGB : 0))
            metric("Disk used", value: snap.diskUsed, icon: "internaldrive", tint: .blue)
            metric("Disk free", value: snap.diskFree, icon: "externaldrive.badge.checkmark", tint: .green)
            metric("Processes", value: "\(snap.processes)", icon: "list.bullet.rectangle", tint: .orange)
            metric("CPU", value: snap.cpuModel, icon: "cpu.fill", tint: .purple, mono: true)
        }
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.text.square.fill").foregroundStyle(healthColor)
                Text("Health Score").font(.headline)
                Spacer()
                Text("\(snap.healthScore)/100").font(.system(.title2, design: .rounded).bold()).foregroundStyle(healthColor)
            }
            ProgressView(value: Double(snap.healthScore), total: 100).tint(healthColor)
            Text(snap.healthMessage).font(.subheadline).foregroundStyle(.secondary)

            if !snap.healthFactors.isEmpty {
                Divider()
                Text("Why this score").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    ForEach(snap.healthFactors) { factor in
                        factorRow(factor)
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    private func factorRow(_ f: HealthFactor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: f.severity == .critical ? "exclamationmark.triangle.fill"
                            : f.severity == .warn ? "exclamationmark.circle.fill"
                            : "checkmark.circle.fill")
                .foregroundStyle(severityColor(f.severity))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(f.name).fontWeight(.medium)
                    Spacer()
                    if f.penalty > 0 {
                        Text("−\(f.penalty) pts").font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(severityColor(f.severity))
                    } else {
                        Text("OK").font(.system(.caption, design: .monospaced).bold()).foregroundStyle(.green)
                    }
                }
                Text(f.currentText).font(.caption).foregroundStyle(.secondary)
                Text(f.thresholdText).font(.caption2).foregroundStyle(.tertiary)
                if f.penalty > 0 {
                    Text(f.advice).font(.caption).foregroundStyle(.blue.opacity(0.85)).padding(.top, 1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(severityColor(f.severity).opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private func severityColor(_ sev: HealthFactor.Severity) -> Color {
        switch sev {
        case .ok: return .green
        case .warn: return .orange
        case .critical: return .red
        }
    }

    private var healthColor: Color {
        switch snap.healthScore {
        case 80...: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }

    private func barColor(_ frac: Double) -> Color {
        switch frac {
        case ..<0.6: return .green
        case ..<0.8: return .yellow
        case ..<0.9: return .orange
        default: return .red
        }
    }

    private func metric(_ title: String, value: String, icon: String, tint: Color, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).foregroundStyle(tint); Text(title).font(.caption).foregroundStyle(.secondary); Spacer() }
            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .system(.title3, design: .rounded).bold())
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }

    @MainActor
    private func refresh() async {
        loading = true
        let s = await StatusService.fetch()
        snap = s
        loading = false
        lastRefresh = Date()
    }
}
