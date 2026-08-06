import SwiftUI

/// In-app AGPL-3.0 license text (from `BundledLegalText`, synced with repo `LICENSE`).
struct LicenseView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(LegalLinks.copyrightLine)
          .font(.footnote)
          .foregroundStyle(.secondary)
        Text(BundledLegalText.licenseAGPL3)
          .font(.system(.footnote, design: .monospaced))
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
        if !BundledLegalText.notice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text("NOTICE")
            .font(.headline)
          Text(BundledLegalText.notice)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
        }
      }
      .padding()
    }
    .navigationTitle("License")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Link(destination: LegalLinks.licenseOnline) {
          Image(systemName: "safari")
        }
        .accessibilityLabel("Open license on GitHub")
      }
    }
  }
}

#Preview {
  NavigationStack { LicenseView() }
}
