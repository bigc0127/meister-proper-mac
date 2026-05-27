import SwiftUI

/// Shared output pane: dark background, lavender monospace text, auto-scrolls to bottom on update.
struct LogPane: View {
    let placeholder: String
    let log: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Text(log.isEmpty ? placeholder : log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.logText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                    Color.clear.frame(height: 1).id("bottomAnchor")
                }
            }
            .background(Color.black.opacity(0.85))
            .clipShape(.rect(cornerRadius: 8))
            .onChange(of: log) { _, _ in
                withAnimation(.linear(duration: 0.08)) {
                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                }
            }
        }
    }
}
