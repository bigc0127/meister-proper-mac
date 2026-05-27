import SwiftUI
import AppKit

struct WelcomeSheet: View {
    @Binding var isPresented: Bool
    @AppStorage("welcome.skip") private var skipForever: Bool = false
    @State private var hasFDA = TCCStatus.hasFullDiskAccess()
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            grantSection
            Divider()
            footer
        }
        .padding(28)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Meister Proper").font(.title2.bold())
                Text("Quick one-time setup to clean everything macOS hides.").foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var grantSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: hasFDA ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(hasFDA ? .green : .orange)
                    .font(.title3)
                Text(hasFDA ? "Full Disk Access: Granted" : "Full Disk Access: Not granted")
                    .font(.headline)
                Spacer()
                Button { recheck() } label: {
                    if checking { ProgressView().controlSize(.small) }
                    else { Label("Re-check", systemImage: "arrow.clockwise") }
                }.buttonStyle(.bordered).controlSize(.small)
            }

            if hasFDA {
                Text("You're all set — every cleanup runs without password prompts.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("macOS hides parts of `~/Library` (Cookies, WebKit, Saved Application State, Trash contents) from any app without Full Disk Access. Without it, those items either fail silently or require an admin password each time.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    label(num: 1, "Click **Open Settings** below — System Settings opens to Full Disk Access.")
                    label(num: 2, "Find **Meister Proper** in the list and toggle it on (or click + and pick it from /Applications).")
                    label(num: 3, "Return here and click **Re-check**.")
                }.padding(.top, 4)

                HStack {
                    Button { openPrivacyPane() } label: {
                        Label("Open Settings → Full Disk Access", systemImage: "arrow.up.right.square")
                    }.buttonStyle(.borderedProminent)
                    Button { revealAppInFinder() } label: {
                        Label("Reveal app", systemImage: "folder")
                    }.help("Drag the highlighted app into the Privacy list")
                }.padding(.top, 6)
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Don't show on launch again", isOn: $skipForever)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Spacer()
            Button("Continue") { isPresented = false }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(hasFDA ? .green : .accentColor)
        }
    }

    private func label(num: Int, _ md: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(num).").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
            Text(md).font(.callout)
        }
    }

    private func openPrivacyPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealAppInFinder() {
        let path = "/Applications/Meister Proper.app"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if let bundle = Bundle.main.bundleURL as URL? {
            NSWorkspace.shared.activateFileViewerSelecting([bundle])
        }
    }

    private func recheck() {
        checking = true
        DispatchQueue.global().async {
            let result = TCCStatus.hasFullDiskAccess()
            DispatchQueue.main.async {
                hasFDA = result
                checking = false
            }
        }
    }
}
