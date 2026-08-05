import SwiftUI
import PrismKit

struct LoginView: View {
  @EnvironmentObject private var state: AppState
  @State private var isSignup = false

  var body: some View {
    Form {
      if let banner = state.banner {
        Section {
          Text(banner)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        TextField("Username", text: $state.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .textContentType(.username)
        SecureField("Password (10+ characters)", text: $state.password)
          .textContentType(isSignup ? .newPassword : .password)
      } header: {
        Text("Account")
      }

      Section {
        Toggle("Create a new account", isOn: $isSignup)
        Button {
          Task {
            if isSignup {
              await state.signup()
            } else {
              await state.login()
            }
          }
        } label: {
          if state.isBusy {
            ProgressView()
          } else {
            Text(isSignup ? "Sign up" : "Sign in")
              .frame(maxWidth: .infinity)
          }
        }
        .disabled(state.isBusy || state.username.isEmpty || state.password.count < 10)
      } footer: {
        Text(
          "Public playground (play.skyphusion.org) uses first-party username/password and a session cookie. Self-host Access mode skips this screen when the boot probe reports authenticated."
        )
      }

      if let err = state.errorMessage {
        Section {
          Text(err)
            .foregroundStyle(.red)
            .font(.footnote)
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    LoginView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
