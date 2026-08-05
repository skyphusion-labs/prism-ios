import SwiftUI
import PrismKit
import StoreKit

struct SettingsView: View {
  @EnvironmentObject private var state: AppState
  @StateObject private var store = StoreManager()
  @State private var draftPlayURL: String = ""
  @State private var draftPlaneURL: String = ""
  @State private var pastedDeviceKey: String = ""

  var body: some View {
    Form {
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

      if state.backend == .playground {
        playgroundSection
      } else {
        controlPlaneSection
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
        row("Kit", "\(PrismKit.name) \(PrismKit.version)")
      } header: {
        Text("Session")
      }

      Section {
        Button("Refresh models") {
          Task { await state.refreshModels() }
        }
        if state.backend == .playground, state.authenticated {
          Button("Sign out", role: .destructive) {
            Task { await state.logout() }
          }
        }
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
    }
    .task(id: state.backend) {
      if state.backend == .controlPlane {
        await store.loadProducts()
      }
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

    Section {
      SecureField("Enrollment token", text: $state.enrollmentToken)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
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
        "Single-use token from the plane operator. The device key (pcp_…) is returned once and stored in the Keychain."
      )
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
          Task { await state.clearDeviceKey() }
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
        "Consumable App Store packs. Device key required so a future plane redeem can attach credit to this account. Server-side receipt redeem is not live yet."
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
}

#Preview {
  NavigationStack {
    SettingsView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
