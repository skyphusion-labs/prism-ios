import SwiftUI
import PrismKit
#if canImport(UIKit)
import UIKit
#endif

/// Control-plane image and video generation (unit-priced doors on play-proxy).
struct MediaGenerateView: View {
  enum Kind: String, CaseIterable, Identifiable {
    case image
    case video
    var id: String { rawValue }
    var title: String {
      switch self {
      case .image: return "Image"
      case .video: return "Video"
      }
    }
  }

  let kind: Kind
  @EnvironmentObject private var state: AppState

  var body: some View {
    VStack(spacing: 0) {
      if let banner = state.banner {
        Text(banner)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .padding(.vertical, 6)
      }

      Form {
        if !state.canUseMediaDoors {
          Section {
            Text("Switch to Control plane and enroll (or paste a pcp_ key) in Settings. Image and video doors are plane-only.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        Section {
          Picker("Model", selection: bindingForModel) {
            ForEach(modelsForKind) { m in
              Text(m.label ?? m.model).tag(Optional(m.model))
            }
          }
          if modelsForKind.isEmpty, state.canUseMediaDoors {
            Text("No \(kind.title.lowercased()) models in catalog. Refresh models in Settings.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Model")
        }

        Section {
          TextField(kind == .image ? "Image prompt" : "Video prompt", text: promptBinding, axis: .vertical)
            .lineLimit(3...8)
          if kind == .video {
            TextField("Optional image URL or data:… (i2v)", text: $state.videoImageRef, axis: .vertical)
              .lineLimit(2...4)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
          Button {
            Task {
              if kind == .image {
                await state.generateImage()
              } else {
                await state.generateVideo()
              }
            }
          } label: {
            if state.mediaBusy {
              ProgressView()
                .frame(maxWidth: .infinity)
            } else {
              Text(kind == .image ? "Generate image" : "Generate video")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(state.mediaBusy || !state.canUseMediaDoors || modelsForKind.isEmpty)
        } header: {
          Text("Prompt")
        } footer: {
          Text(
            kind == .image
              ? "POST /v1/images/generations. Prefer xai/ image models; some @cf/ models need different input shapes upstream."
              : "POST /v1/videos/generations. Long-running; may time out if the plane UPSTREAM_TIMEOUT is short. Optional image enables i2v."
          )
        }

        if let status = state.mediaStatus {
          Section {
            Text(status).font(.footnote).foregroundStyle(.secondary)
          }
        }
        if let err = state.mediaError {
          Section {
            Text(err).font(.footnote).foregroundStyle(.red)
          }
        }

        if kind == .image, let b64 = state.lastImageBase64, let uiImage = decodeImage(b64) {
          Section {
            Image(uiImage: uiImage)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 360)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let model = state.lastImageModel {
              Text(model).font(.caption2).foregroundStyle(.secondary)
            }
          } header: {
            Text("Result")
          }
        }

        if kind == .video, let urlStr = state.lastVideoURL {
          Section {
            if let url = URL(string: urlStr), url.scheme?.hasPrefix("http") == true {
              Link("Open video", destination: url)
              Text(urlStr)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            } else {
              Text("Inline video asset (\(urlStr.prefix(48))…)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let model = state.lastVideoModel {
              Text(model).font(.caption2).foregroundStyle(.secondary)
            }
          } header: {
            Text("Result")
          }
        }
      }
    }
    .navigationTitle(kind.title)
  }

  private var modelsForKind: [ModelEntry] {
    kind == .image ? state.imageModels : state.videoModels
  }

  private var bindingForModel: Binding<String?> {
    switch kind {
    case .image:
      return $state.selectedImageModelId
    case .video:
      return $state.selectedVideoModelId
    }
  }

  private var promptBinding: Binding<String> {
    switch kind {
    case .image: return $state.imagePrompt
    case .video: return $state.videoPrompt
    }
  }

  #if canImport(UIKit)
  private func decodeImage(_ b64: String) -> UIImage? {
    var s = b64
    if let range = s.range(of: "base64,") {
      s = String(s[range.upperBound...])
    }
    guard let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else { return nil }
    return UIImage(data: data)
  }
  #else
  private func decodeImage(_ b64: String) -> Never? { nil }
  #endif
}

#Preview {
  NavigationStack {
    MediaGenerateView(kind: .image)
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
