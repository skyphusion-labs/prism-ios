import SwiftUI

/// In-app AGPL-3.0 license text (bundled from repo `LICENSE`).
struct LicenseView: View {
  private let text: String

  init() {
    self.text = Self.loadBundled(named: "LICENSE")
      ?? "License text missing from the app bundle. See \(LegalLinks.licenseOnline.absoluteString)"
  }

  var body: some View {
    ScrollView {
      Text(text)
        .font(.system(.footnote, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
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

  private static func loadBundled(named name: String) -> String? {
    // Prefer exact resource name (App/Legal/LICENSE via xcodegen).
    if let url = Bundle.main.url(forResource: name, withExtension: nil)
      ?? Bundle.main.url(forResource: name, withExtension: "txt")
      ?? Bundle.main.url(forResource: name, withExtension: "", subdirectory: "Legal")
    {
      return try? String(contentsOf: url, encoding: .utf8)
    }
    // Fallback: any path ending in LICENSE inside the bundle.
    if let urls = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) {
      for url in urls where url.lastPathComponent == name {
        return try? String(contentsOf: url, encoding: .utf8)
      }
    }
    return nil
  }
}

#Preview {
  NavigationStack { LicenseView() }
}
