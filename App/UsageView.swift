import SwiftUI
import PrismKit

/// Control-plane dual-pool balance + period meter (`GET /v1/usage` + last `/v1/me` snapshot).
struct UsageView: View {
  @EnvironmentObject private var state: AppState
  @State private var busy = false
  @State private var error: String?
  @State private var detail: UsageSummary?

  var body: some View {
    List {
      Section {
        if let bal = state.planeBalance, !bal.isEmpty {
          LabeledContent("Spendable", value: bal)
        }
        if let label = state.planeClientLabel {
          LabeledContent("Client", value: label)
        }
        LabeledContent("Plane", value: state.planeHealthLabel)
        Button {
          Task { await refresh() }
        } label: {
          if busy {
            ProgressView()
          } else {
            Label("Refresh usage", systemImage: "arrow.clockwise")
          }
        }
        .disabled(busy || !state.deviceKeyPresent)
        .frame(minHeight: 44)
      } header: {
        Text("Account")
      } footer: {
        Text("Allowance spends first; unused expires at period roll. Prepaid credit never expires.")
      }

      Section {
        let lines = detail?.dualPoolLines ?? state.planeUsageLines
        if lines.isEmpty {
          Text(state.deviceKeyPresent ? "Pull refresh or open after a metered call." : "Enroll a device key first.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          ForEach(lines, id: \.self) { line in
            Text(line)
              .font(.body)
              .textSelection(.enabled)
          }
        }
      } header: {
        Text("Dual pool")
      }

      if let period = detail?.periodDetailLines, !period.isEmpty {
        Section {
          ForEach(period, id: \.self) { line in
            Text(line)
              .font(.body)
              .textSelection(.enabled)
          }
        } header: {
          Text("This period")
        } footer: {
          Text(
            "Unmetered means the plane served the call but could not price it (no free ride forever; reconcile may true up). Prefer reconciled spend when showing one number."
          )
        }
      }

      if let err = error {
        Section {
          Text(err)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
    }
    .navigationTitle("Usage")
    .task { await refresh() }
    .refreshable { await refresh() }
  }

  private func refresh() async {
    guard state.deviceKeyPresent else { return }
    busy = true
    error = nil
    defer { busy = false }
    do {
      detail = try await state.fetchPlaneUsage()
      await state.refreshPlaneBalanceOnly()
    } catch {
      self.error = prismUserFacingError(error)
    }
  }
}

#Preview {
  NavigationStack {
    UsageView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
