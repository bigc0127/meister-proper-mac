import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview      = "Overview"
    case clean         = "Clean"
    case orphans       = "App Leftovers"
    case purge         = "Project Purge"
    case installer     = "Installers"
    case uninstall     = "App Uninstall"
    case extraCleanup  = "Extra Cleanup"
    case optimize      = "Optimize"
    case launchAgents  = "LaunchAgents"
    case analyze       = "Analyze"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:      return "gauge.medium"
        case .clean:         return "sparkles"
        case .orphans:       return "questionmark.app.dashed"
        case .optimize:      return "wrench.and.screwdriver"
        case .purge:         return "folder.badge.minus"
        case .installer:     return "shippingbox"
        case .analyze:       return "chart.pie"
        case .uninstall:     return "trash"
        case .launchAgents:  return "play.circle"
        case .extraCleanup:  return "broom"
        }
    }
}

struct ContentView: View {
    @State private var selection: AppSection = .overview
    @State private var showWelcome: Bool = false
    @AppStorage("welcome.skip") private var skipWelcome: Bool = false

    var body: some View {
        rootSplit
            .onAppear {
                if !skipWelcome && !TCCStatus.hasFullDiskAccess() {
                    showWelcome = true
                }
            }
            .sheet(isPresented: $showWelcome) {
                WelcomeSheet(isPresented: $showWelcome)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showWelcome = true } label: { Image(systemName: "questionmark.circle") }
                        .help("Setup / Full Disk Access status")
                }
            }
    }

    private var rootSplit: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: AppSection.overview) {
                    Label(AppSection.overview.rawValue, systemImage: AppSection.overview.icon)
                }
                Section("Cleanup") {
                    ForEach([AppSection.clean, .orphans, .purge, .installer, .uninstall, .extraCleanup], id: \.self) { (s: AppSection) in
                        NavigationLink(value: s) { Label(s.rawValue, systemImage: s.icon) }
                    }
                }
                Section("Maintenance") {
                    ForEach([AppSection.optimize, .launchAgents, .analyze], id: \.self) { (s: AppSection) in
                        NavigationLink(value: s) { Label(s.rawValue, systemImage: s.icon) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch selection {
            case .overview:      OverviewView()
            case .clean:         CleanView()
            case .orphans:       OrphansView()
            case .optimize:      OptimizeView()
            case .purge:         PurgeView()
            case .installer:     InstallerView()
            case .analyze:       AnalyzeView()
            case .uninstall:     UninstallPickerView()
            case .launchAgents:  LaunchAgentsView()
            case .extraCleanup:  ExtraCleanupView()
            }
        }
    }
}
