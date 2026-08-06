import SwiftUI
import PrismKit
import StoreKit

struct SettingsView: View {
  @EnvironmentObject private var state: AppState
  @StateObject private var store = StoreManager()
  @State private var draftPlayURL: String = ""
  @State private var draftPlaneURL: String = ""
  @State private var pastedDeviceKey: String = ""
  @State private var confirmClearKey = false
  @State private var chatExportURL: ExportURL?
  @State private var showImportPicker = false
  @State private var importMessage: String?
  @State private var pendingImportData: Data?
  @State private var importPreview: AppState.ChatImportPreview?
  @State private var showImportConfirm = false

  var body: some View {
    Form {
      if state.backend == .controlPlane, state.deviceKeyPresent {
        Section {
          Toggle(
            "Require \(BiometricLock.biometryLabel)",
            isOn: Binding(
              get: { state.biometricLockEnabled },
              set: { state.setBiometricLockEnabled($0) }
            )
          )
          .disabled(!BiometricLock.isAvailable())
        } header: {
          Text("Lock")
        } footer: {
          if BiometricLock.isAvailable() {
            Text(
              "When enabled, Prism asks for \(BiometricLock.biometryLabel) (or your device passcode) after launch and when returning from background. Device key stays in Keychain either way."
            )
          } else {
            Text("Biometrics are not available on this device. Device key remains in Keychain.")
          }
        }
      }

      if state.showDeveloperSettings {
        Section {
          Picker("Backend", selection: Binding(
            get: { state.backend },
            set: { state.setBackend($0) }
          )) {
            ForEach(BackendKind.allCases) { kind in
              Text(kind.title).tag(kind)
            }
          }
          .pickerStyle(.segmented)
        } header: {
          Text("Backend")
        } footer: {
          Text(
            "Playground is play.skyphusion.org (session cookie). Control plane is play-proxy (pcp_ device key, metered)."
          )
        }
      }

      if state.backend == .playground {
        playgroundSection
      } else {
        controlPlaneSection
        balanceSection
        topUpSection
      }

      Section {
        row("Mode", state.authMode ?? "unknown")
        if state.backend == .playground {
          row("Signed in", state.authenticated ? (state.sessionUsername ?? "yes") : "no")
        } else {
          row("Device key", state.deviceKeyPresent ? "stored" : "none")
          if let label = state.planeClientLabel {
            row("Client", label)
          }
          if let bal = state.planeBalance {
            row("Balance", bal)
          }
        }
        row("Models", "\(state.models.count)")
        if state.backend == .controlPlane {
          row("Plane health", state.planeHealthLabel)
        }
        row("Kit", "\(PrismKit.name) \(PrismKit.version)")
      } header: {
        Text("Session")
      }

      Section {
        Button("Refresh models") {
          Task { await state.refreshModels() }
        }
        if state.backend == .controlPlane {
          Button("Check plane health") {
            Task { await state.probePlaneHealth() }
          }
        }
        if state.backend == .playground, state.authenticated {
          Button("Sign out", role: .destructive) {
            Task { await state.logout() }
          }
        }
      }

      Section {
        Toggle("Developer options", isOn: Binding(
          get: { state.showDeveloperSettings },
          set: { state.setShowDeveloperSettings($0) }
        ))
      } header: {
        Text("Advanced")
      } footer: {
        Text("Unlocks playground backend and base-URL overrides. Product default is Control plane.")
      }

      Section {
        Link(destination: URL(string: "https://skyphusion.org")!) {
          Label("skyphusion.org", systemImage: "globe")
        }
        Link(destination: URL(string: "https://skyphusion.org/privacy.html")!) {
          Label("Privacy policy", systemImage: "hand.raised")
        }
        Link(destination: URL(string: "https://play.skyphusion.org")!) {
          Label("Prism playground (web)", systemImage: "macwindow")
        }
        Link(destination: URL(string: "https://status.skyphusion.org")!) {
          Label("Status", systemImage: "heart.text.square")
        }
        Link(destination: URL(string: "mailto:support@skyphusion.org")!) {
          Label("support@skyphusion.org", systemImage: "envelope")
        }
      } header: {
        Text("About")
      } footer: {
        Text("Prism is an AGPL product of SkyPhusion Labs. Kit \(PrismKit.version).")
      }

      if let err = state.errorMessage {
        Section {
          Text(err).foregroundStyle(.red).font(.footnote)
        }
      }
    }
    .navigationTitle("Settings")
    .onAppear {
      draftPlayURL = state.baseURLString
      draftPlaneURL = state.controlPlaneURLString
      store.redeemHandler = { jws in
        try await state.redeemStoreTransaction(jws: jws)
      }
      store.onRedeemed = {
        await state.refreshModels()
      }
    }
    .task(id: state.backend) {
      if state.backend == .controlPlane {
        store.redeemHandler = { jws in
          try await state.redeemStoreTransaction(jws: jws)
        }
        store.onRedeemed = {
          await state.refreshModels()
        }
        await store.loadProducts()
      }
    }
  }

  @ViewBuilder
  private var balanceSection: some View {
    Section {
      if state.planeUsageLines.isEmpty {
        Text(state.planeBalance ?? "Refresh models to load balance.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        ForEach(state.planeUsageLines, id: \.self) { line in
          Text(line)
            .font(.footnote)
        }
      }
      Button("Refresh balance") {
        Task { await state.refreshModels() }
      }
    } header: {
      Text("Balance")
    } footer: {
      Text("Spendable is prepaid + monthly allowance. Top-ups redeem via StoreKit to the plane.")
    }
  }

  @ViewBuilder
  private var playgroundSection: some View {
    Section {
      TextField("Base URL", text: $draftPlayURL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.URL)
        .textContentType(.URL)
      Button("Apply and reload") {
        state.baseURLString = draftPlayURL
        state.rebuildClients()
        Task { await state.refreshModels() }
      }
      Button("Use play.skyphusion.org") {
        draftPlayURL = PrismClient.playBaseURL.absoluteString
        state.baseURLString = draftPlayURL
        state.rebuildClients()
        Task { await state.refreshModels() }
      }
    } header: {
      Text("Playground server")
    } footer: {
      Text(
        "Public playground needs signup. Self-host Access mode can chat without this app's login when the Worker trusts Access (or local anonymous)."
      )
    }
  }

  @ViewBuilder
  private var controlPlaneSection: some View {
    if state.showDeveloperSettings {
      Section {
        TextField("Base URL", text: $draftPlaneURL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
          .textContentType(.URL)
        Button("Apply URL") {
          state.controlPlaneURLString = draftPlaneURL
          state.rebuildClients(clearSession: false)
          Task { await state.refreshModels() }
        }
        Button("Use play-proxy.skyphusion.org") {
          draftPlaneURL = ControlPlaneClient.productionBaseURL.absoluteString
          state.controlPlaneURLString = draftPlaneURL
          state.rebuildClients(clearSession: false)
          Task { await state.refreshModels() }
        }
      } header: {
        Text("Control plane server")
      }
    }

    Section {
      SecureField("Enrollment token", text: $state.enrollmentToken)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button {
        _ = state.pasteEnrollmentFromClipboard()
      } label: {
        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
      }
      Button {
        Task { await state.enrollPlane() }
      } label: {
        if state.isBusy {
          ProgressView()
        } else {
          Text("Enroll device")
        }
      }
      .disabled(state.isBusy || state.enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    } header: {
      Text("Enrollment")
    } footer: {
      Text(
        "Single-use token from the plane operator. The device key (pcp_…) is returned once and stored in the Keychain. Clipboard paste accepts a token or a full pcp_ key."
      )
    }

    Section {
      Button {
        guard let data = state.exportSessionsJSON() else { return }
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent("prism-chats-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url, options: .atomic)
        chatExportURL = ExportURL(url: url)
      } label: {
        Label("Export local chats (JSON)", systemImage: "square.and.arrow.up")
      }
      .frame(minHeight: 44)
      .sheet(item: $chatExportURL) { item in
        #if canImport(UIKit)
        ChatExportActivityView(items: [item.url])
        #endif
      }
      Button {
        showImportPicker = true
      } label: {
        Label("Import chats (JSON)", systemImage: "square.and.arrow.down")
      }
      .frame(minHeight: 44)
      .fileImporter(
        isPresented: $showImportPicker,
        allowedContentTypes: [.json, .data],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          guard let url = urls.first else { return }
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          do {
            let data = try Data(contentsOf: url)
            let preview = try state.previewImportSessionsJSON(data)
            pendingImportData = data
            importPreview = preview
            showImportConfirm = true
          } catch {
            importMessage = prismUserFacingError(error)
            pendingImportData = nil
            importPreview = nil
          }
        case .failure(let err):
          importMessage = err.localizedDescription
        }
      }
      .confirmationDialog(
        importConfirmTitle,
        isPresented: $showImportConfirm,
        titleVisibility: .visible
      ) {
        Button("Merge (file wins on id clash)") {
          applyPendingImport(replace: false)
        }
        Button("Replace all local chats", role: .destructive) {
          applyPendingImport(replace: true)
        }
        Button("Cancel", role: .cancel) {
          pendingImportData = nil
          importPreview = nil
        }
      } message: {
        Text(importConfirmMessage)
      }
      if let importMessage {
        Text(importMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Text(
        "Control plane never stores conversation text. Export/import for backup. "
          + "Import previews the file, then merge or replace. "
          + "Playground cloud history: Chats list → Sync from playground cloud."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    } header: {
      Text("Chat backup")
    }

    Section {
      SecureField("Or paste pcp_ device key", text: $pastedDeviceKey)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Save device key") {
        Task {
          await state.saveDeviceKey(pastedDeviceKey)
          pastedDeviceKey = ""
        }
      }
      .disabled(pastedDeviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if state.deviceKeyPresent {
        Button("Clear device key", role: .destructive) {
          confirmClearKey = true
        }
        .confirmationDialog(
          "Clear device key?",
          isPresented: $confirmClearKey,
          titleVisibility: .visible
        ) {
          Button("Clear key", role: .destructive) {
            Task { await state.clearDeviceKey() }
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("This device will need a new enrollment token (or paste of a pcp_ key) before chatting or generating again.")
        }
      }
    } header: {
      Text("Device key")
    }
  }

  @ViewBuilder
  private var topUpSection: some View {
    Section {
      if store.isLoading {
        HStack {
          ProgressView()
          Text("Loading products…")
            .foregroundStyle(.secondary)
        }
      } else if store.sortedProducts.isEmpty {
        Button("Reload products") {
          Task { await store.loadProducts() }
        }
        .disabled(!state.deviceKeyPresent || store.isPurchasing)
      } else {
        ForEach(store.sortedProducts, id: \.id) { product in
          Button {
            Task { _ = await store.purchase(product) }
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                if let usd = store.creditUSD(for: product.id) {
                  Text("\(usd) USD prepaid credit (intended)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                  Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              }
              Spacer()
              if store.isPurchasing {
                ProgressView()
              } else {
                Text(product.displayPrice)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .disabled(!state.deviceKeyPresent || store.isPurchasing)
        }
      }

      if let msg = store.statusMessage {
        Text(msg)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      if let err = store.errorMessage {
        Text(err)
          .font(.footnote)
          .foregroundStyle(.red)
      }
      if let tx = store.lastTransactionId {
        row("Last transaction", tx)
      }
    } header: {
      Text("Top up")
    } footer: {
      Text(
        "Consumable App Store packs. After purchase, the app sends the StoreKit 2 signed transaction to the plane (POST /v1/store/redeem) and refreshes balance."
      )
    }
  }

  @ViewBuilder
  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
  }

  private var importConfirmTitle: String {
    if let p = importPreview {
      return "Import \(p.count) chat\(p.count == 1 ? "" : "s")?"
    }
    return "Import chats?"
  }

  private var importConfirmMessage: String {
    guard let p = importPreview else {
      return "Merge keeps local chats and overwrites matching ids. Replace discards current local list."
    }
    var lines: [String] = [
      "\(p.newIds) new · \(p.overlappingIds) overlap existing ids.",
    ]
    if !p.titles.isEmpty {
      let sample = p.titles.prefix(3).joined(separator: " · ")
      lines.append("e.g. \(sample)")
    }
    lines.append("Merge keeps locals and overwrites matching ids. Replace discards the current list.")
    return lines.joined(separator: "\n")
  }

  private func applyPendingImport(replace: Bool) {
    guard let data = pendingImportData else { return }
    defer {
      pendingImportData = nil
      importPreview = nil
    }
    do {
      let result = try state.importSessionsJSON(data, replace: replace)
      if replace {
        importMessage = "Replaced local chats with \(result.count) from file."
      } else {
        importMessage =
          "Merged \(result.count) from file (\(result.newIds) new, \(result.overlappingIds) updated)."
      }
    } catch {
      importMessage = prismUserFacingError(error)
    }
  }
}

private struct ExportURL: Identifiable {
  let id = UUID()
  let url: URL
}

#if canImport(UIKit)
import UIKit
private struct ChatExportActivityView: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
  NavigationStack {
    SettingsView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
