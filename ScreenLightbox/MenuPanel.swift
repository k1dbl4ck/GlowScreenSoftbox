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

            Text("Turns on when a camera is in use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Dim Level")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $overlay.dimAmount, in: 0.05...0.85)
                Text("\(Int(overlay.dimAmount * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .disabled(!overlay.isEnabled)
            .opacity(overlay.isEnabled ? 1 : 0.45)

            Divider()
            
            HStack {
                Text("Hide apps that aren't fullscreen")
                    .font(.headline)
                Spacer()
                Toggle("Hide apps that aren't fullscreen", isOn: $overlay.hideNonFullscreenApps)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Hide apps that aren't fullscreen")
            }
            
            HStack {
                Text("Enable when camera starts")
                    .font(.headline)
                Spacer()
                Toggle("Enable when camera starts", isOn: $overlay.enableOnCameraStart)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Enable when camera starts")
            }
            
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
