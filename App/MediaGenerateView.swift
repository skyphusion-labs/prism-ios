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
          // Non-optional tags: Optional tags silently desync and fall back to first model (Veo).
          Picker("Model", selection: nonOptionalModelBinding) {
            ForEach(modelsForKind) { m in
              Text(shortLabel(m)).tag(m.model)
            }
          }
          if let id = currentModelId {
            Text(id)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
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
          // Only show image ref for models that accept it (i2i dual / required). Pure t2i hides the field.
          if kind == .image, selectedImageAcceptsRef {
            TextField(imageRefPlaceholder, text: $state.imageImageRef, axis: .vertical)
              .lineLimit(2...4)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
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
          Text(kind == .image ? imageFooter : videoFooter)
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

        if kind == .image, state.lastImageBase64 != nil || state.lastImageURL != nil {
          Section {
            if let b64 = state.lastImageBase64, let uiImage = decodeImage(b64) {
              Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let urlStr = state.lastImageURL, let url = URL(string: urlStr) {
              AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                  img.resizable().scaledToFit().frame(maxHeight: 360)
                case .failure:
                  Link("Open image URL", destination: url)
                case .empty:
                  ProgressView()
                @unknown default:
                  EmptyView()
                }
              }
              Text(urlStr)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            } else {
              Text("Image payload present but could not render (not base64 and no URL).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
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

  private var currentModelId: String? {
    kind == .image ? state.selectedImageModelId : state.selectedVideoModelId
  }

  private var nonOptionalModelBinding: Binding<String> {
    switch kind {
    case .image:
      return Binding(
        get: { state.selectedImageModelId ?? state.imageModels.first?.model ?? "" },
        set: { state.selectedImageModelId = $0.isEmpty ? nil : $0 }
      )
    case .video:
      return Binding(
        get: { state.selectedVideoModelId ?? state.videoModels.first?.model ?? "" },
        set: { state.selectedVideoModelId = $0.isEmpty ? nil : $0 }
      )
    }
  }

  private var promptBinding: Binding<String> {
    switch kind {
    case .image: return $state.imagePrompt
    case .video: return $state.videoPrompt
    }
  }

  private func shortLabel(_ m: ModelEntry) -> String {
    let base = m.label ?? m.model
    let caps = m.capabilities ?? []
    if caps.contains("image-input-required") { return "\(base) · i2i only" }
    if caps.contains("image-input"), (m.type == "image" || kind == .image) {
      return "\(base) · i2i / +ref"
    }
    return base
  }

  private var selectedImageAcceptsRef: Bool {
    let caps = state.selectedImageModel?.capabilities ?? []
    return caps.contains("image-input") || caps.contains("image-input-required")
  }

  private var imageRefPlaceholder: String {
    let caps = state.selectedImageModel?.capabilities ?? []
    if caps.contains("image-input-required") {
      return "Required reference image URL or data:… (i2i)"
    }
    return "Reference image URL or data:… (i2i / edit / multi-ref)"
  }

  private var imageFooter: String {
    let caps = state.selectedImageModel?.capabilities ?? []
    if caps.contains("image-input-required") {
      return "This model is image-to-image only. Paste an https or data: reference above."
    }
    if caps.contains("image-input") {
      return "Dual-mode: works from prompt alone, or paste a reference for i2i/edit (Flux 2 multi-ref, nano-banana, gpt-image, Grok image). Prefer data: for Flux 2."
    }
    return "Pure text-to-image. Switch to a · i2i / +ref model to condition on a reference image."
  }

  private var videoFooter: String {
    let mid = state.selectedVideoModelId ?? ""
    if mid.hasPrefix("minimax/hailuo") {
      return "Hailuo is image-to-video only: paste an https image URL above. For text-only use Veo or Seedance Fast."
    }
    if mid.hasPrefix("xai/grok-imagine-video") {
      return "Grok video still returns CF 7003 on this plane. Prefer google/veo-3.1-fast or bytedance/seedance-2.0-fast."
    }
    return "POST /v1/videos/generations. Veo and Seedance Fast are most reliable. Full Seedance may take up to ~3 min."
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
