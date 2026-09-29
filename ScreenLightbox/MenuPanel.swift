import AppKit
import SwiftUI

struct MenuPanel: View {
    @EnvironmentObject private var overlay: OverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Screen Lightbox")
                    .font(.headline)
                Spacer()
                Toggle("Dim screens", isOn: $overlay.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Dim screens")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Dim")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $overlay.dimAmount, in: 0.05...0.85)
                Text("\(Int(overlay.dimAmount * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .disabled(!overlay.isEnabled)
            .opacity(overlay.isEnabled ? 1 : 0.45)

            Toggle("Hide apps that aren't fullscreen", isOn: $overlay.hideNonFullscreenApps)
                .toggleStyle(.checkbox)

            Divider()

            Button("Quit Screen Lightbox") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
    }
}
