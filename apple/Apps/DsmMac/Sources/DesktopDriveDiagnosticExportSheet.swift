import AppKit
import DsmLocalization
import SwiftUI
import UniformTypeIdentifiers

struct DesktopDriveDiagnosticExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: String
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isExporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("desktopDrive.diagnostics.title"))
                .font(.title2.weight(.semibold))

            Text(L10n.string("desktopDrive.diagnostics.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(preview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .accessibilityLabel(
                L10n.string("desktopDrive.diagnostics.preview")
            )

            if let statusMessage {
                Label(
                    statusMessage,
                    systemImage: statusIsError
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(statusIsError ? .red : .secondary)
            }

            HStack {
                Spacer()
                Button(L10n.string("desktopDrive.diagnostics.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    export()
                } label: {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.string("desktopDrive.diagnostics.export"))
                    }
                }
                .disabled(isExporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 460)
    }

    private func export() {
        isExporting = true
        defer { isExporting = false }

        let panel = NSSavePanel()
        panel.title = L10n.string("desktopDrive.diagnostics.saveTitle")
        panel.nameFieldStringValue = "LanStash-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(preview.utf8).write(to: url, options: .atomic)
            statusMessage = L10n.string(
                "desktopDrive.diagnostics.exported"
            )
            statusIsError = false
        } catch {
            statusMessage = L10n.string(
                "desktopDrive.diagnostics.exportFailed"
            )
            statusIsError = true
        }
    }
}
