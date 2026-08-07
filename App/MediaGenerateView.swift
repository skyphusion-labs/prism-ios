import SwiftUI
import PrismKit
import PhotosUI
import AVKit
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
  @State private var photoItem: PhotosPickerItem?
  @State private var sharePayload: SharePayload?

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
          if state.backend == .controlPlane {
            TextField("Search models", text: $state.modelSearch)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
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
            Text("No \(kind.title.lowercased()) models match. Clear search or refresh models in Settings.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Model")
        }

        Section {
          TextField(kind == .image ? "Image prompt" : "Video prompt", text: promptBinding, axis: .vertical)
            .lineLimit(3...8)
            .font(.body)
            .accessibilityLabel(kind == .image ? "Image prompt" : "Video prompt")

          if kind == .image, selectedImageAcceptsRef {
            refSection
          }
          if kind == .video {
            videoRefSection
            videoDurationPicker
          }

          if let preview = kind == .image ? state.imageSpendPreview : state.videoSpendPreview {
            Text(preview)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .accessibilityLabel(preview)
          }

          if state.mediaBusy {
            HStack {
              ProgressView()
              Text(elapsedLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
              Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Generating, \(state.mediaElapsedSeconds) seconds elapsed")
            Button(role: .destructive) {
              state.cancelMedia()
            } label: {
              Text("Cancel generation")
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Cancel generation")
          } else {
            Button {
              if kind == .image {
                state.generateImage()
              } else {
                state.generateVideo()
              }
            } label: {
              Text(kind == .image ? "Generate image" : "Generate video")
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .disabled(!state.canUseMediaDoors || modelsForKind.isEmpty)
            .accessibilityLabel(kind == .image ? "Generate image" : "Generate video")

            if kind == .image, state.mediaError != nil,
               !state.imagePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
              Button {
                state.retryLastImage()
              } label: {
                Label("Retry image (same prompt)", systemImage: "arrow.clockwise")
                  .frame(maxWidth: .infinity)
                  .frame(minHeight: 44)
              }
              .accessibilityLabel("Retry image with same prompt")
            }
            if kind == .video, state.mediaError != nil,
               !state.videoPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !state.videoImageRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
              Button {
                state.retryLastVideo()
              } label: {
                Label("Retry video (same prompt)", systemImage: "arrow.clockwise")
                  .frame(maxWidth: .infinity)
                  .frame(minHeight: 44)
              }
              .accessibilityLabel("Retry video with same prompt")
            }
          }
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
          imageResultSection
        }

        if kind == .video, let urlStr = state.lastVideoURL {
          videoResultSection(urlStr)
        }

        let history = state.mediaHistory.filter { $0.kind == (kind == .image ? .image : .video) }
        if !history.isEmpty {
          Section {
            ForEach(history) { item in
              VStack(alignment: .leading, spacing: 6) {
                Button {
                  state.restoreMediaHistoryItem(item)
                } label: {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(item.model)
                      .font(.caption)
                      .foregroundStyle(.primary)
                    Text(item.prompt)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .frame(minHeight: 44)
                }
                .accessibilityLabel("Restore \(item.kind.rawValue) from \(item.model)")
                if item.kind == .image, item.imageDataURL != nil {
                  HStack(spacing: 12) {
                    Button {
                      state.useMediaHistoryInChat(item)
                    } label: {
                      Label("Use in chat", systemImage: "bubble.left")
                        .font(.caption)
                    }
                    .accessibilityLabel("Use history image in chat")
                    Button {
                      state.animateMediaHistory(item)
                    } label: {
                      Label("Animate", systemImage: "film")
                        .font(.caption)
                    }
                    .accessibilityLabel("Animate history image")
                  }
                }
              }
            }
          } header: {
            HStack {
              Text("History (this session)")
              Spacer()
              Button("Clear") {
                state.clearMediaHistory()
              }
              .font(.caption)
              .accessibilityLabel("Clear media history")
            }
          } footer: {
            Text(
              "Newest first. Tap a row to restore model, prompt, and last result. "
                + "Use in chat / Animate hand off to Chat or Video. Session-only."
            )
          }
        }
      }
    }
    .navigationTitle(kind.title)
    .onChange(of: photoItem) { item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          let mime = "image/jpeg"
          if kind == .image {
            state.setImageReferenceData(data, mime: mime)
          } else {
            state.setVideoReferenceData(data, mime: mime)
          }
        }
        photoItem = nil
      }
    }
    .sheet(item: $sharePayload) { payload in
      ActivityView(items: payload.items)
    }
  }

  @ViewBuilder
  private var refSection: some View {
    TextField(imageRefPlaceholder, text: $state.imageImageRef, axis: .vertical)
      .lineLimit(2...4)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
    PhotosPicker(selection: $photoItem, matching: .images) {
      Label("Choose photo for reference", systemImage: "photo.on.rectangle")
    }
    if state.lastImageBase64 != nil || state.lastImageURL != nil {
      Button("Use last result as reference") {
        state.useLastImageAsReference(forVideo: false)
      }
    }
    if !state.imageImageRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Button("Clear reference", role: .destructive) {
        state.clearImageReference()
      }
      .accessibilityLabel("Clear image reference")
    }
  }

  @ViewBuilder
  private var videoRefSection: some View {
    TextField("Optional image URL or data:… (i2v)", text: $state.videoImageRef, axis: .vertical)
      .lineLimit(2...4)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
    PhotosPicker(selection: $photoItem, matching: .images) {
      Label("Choose photo for i2v", systemImage: "photo.on.rectangle")
    }
    if state.lastImageBase64 != nil || state.lastImageURL != nil {
      Button("Use last image as first frame") {
        state.useLastImageAsReference(forVideo: true)
      }
    }
    if !state.videoImageRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Button("Clear reference", role: .destructive) {
        state.clearVideoReference()
      }
      .accessibilityLabel("Clear video reference")
    }
  }

  @ViewBuilder
  private var imageResultSection: some View {
    Section {
      if let b64 = state.lastImageBase64, let uiImage = decodeImage(b64) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 360)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        #if canImport(UIKit)
        Button {
          UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
          state.mediaStatus = "Saved to Photos"
        } label: {
          Label("Save to Photos", systemImage: "square.and.arrow.down")
        }
        Button {
          sharePayload = SharePayload(items: [uiImage])
        } label: {
          Label("Share", systemImage: "square.and.arrow.up")
        }
        #endif
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
        Button {
          sharePayload = SharePayload(items: [url])
        } label: {
          Label("Share URL", systemImage: "square.and.arrow.up")
        }
      } else {
        Text("Image payload present but could not render.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      if let model = state.lastImageModel {
        Text(model).font(.caption2).foregroundStyle(.secondary)
      }
      Button {
        state.useLastImageInChat()
      } label: {
        Label("Use in chat", systemImage: "bubble.left")
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(minHeight: 44)
      }
      .accessibilityLabel("Use last image in chat")
      .accessibilityHint("Attaches the image to the chat draft and opens Chat")
      Button {
        state.animateLastImage()
      } label: {
        Label("Animate (video)", systemImage: "film")
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(minHeight: 44)
      }
      .accessibilityLabel("Animate last image as video")
      .accessibilityHint("Sets the image as the video first frame and opens Video")
    } header: {
      Text("Result")
    }
  }

  @ViewBuilder
  private func videoResultSection(_ urlStr: String) -> some View {
    Section {
      if let url = Self.playableVideoURL(urlStr) {
        // Fresh player per URL so Range-capable play-proxy media reloads cleanly.
        VideoPlayer(player: AVPlayer(url: url))
          .frame(minHeight: 220)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .id(url.absoluteString)
        Link("Open in browser", destination: url)
        Text(url.absoluteString)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        Button {
          sharePayload = SharePayload(items: [url])
        } label: {
          Label("Share", systemImage: "square.and.arrow.up")
        }
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
    } footer: {
      Text("Grok videos stream from play-proxy with HTTP Range. If playback fails, Open in browser.")
    }
  }

  /// Prefer URLComponents so signed media tokens with dots stay intact.
  private static func playableVideoURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let u = URL(string: trimmed), u.scheme?.hasPrefix("http") == true { return u }
    if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
       let u = URL(string: encoded),
       u.scheme?.hasPrefix("http") == true
    {
      return u
    }
    return nil
  }

  private var elapsedLabel: String {
    let s = state.mediaElapsedSeconds
    let m = s / 60
    let r = s % 60
    if kind == .video {
      if m > 0 {
        return String(format: "Elapsed %d:%02d · often 1-3 min · lock-safe poll", m, r)
      }
      return "Elapsed \(s)s · often 1-3 min · lock-safe poll"
    }
    if m > 0 {
      return String(format: "Elapsed %d:%02d", m, r)
    }
    return "Elapsed \(s)s"
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
        set: { state.selectImageModel($0) }
      )
    case .video:
      return Binding(
        get: { state.selectedVideoModelId ?? state.videoModels.first?.model ?? "" },
        set: { state.selectVideoModel($0) }
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
    var parts = [base]
    if let p = m.priceLabel { parts.append(p) }
    let caps = m.capabilities ?? []
    if caps.contains("image-input-required") {
      parts.append("i2i only")
    } else if caps.contains("image-input"), kind == .image {
      parts.append("i2i / +ref")
    }
    return parts.joined(separator: " · ")
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
      return "Image-to-image only. Use Choose photo or paste an https / data: URL."
    }
    if caps.contains("image-input") {
      return "Dual-mode: prompt alone works, or attach a reference for i2i/edit. Prefer data: / photo for Flux 2."
    }
    return "Pure text-to-image. Switch to a · i2i / +ref model to condition on a reference."
  }

  private var videoDurationLimits: VideoDurationLimits {
    VideoDurationCatalog.limits(for: state.selectedVideoModelId ?? "")
  }

  @ViewBuilder
  private var videoDurationPicker: some View {
    let limits = videoDurationLimits
    Picker("Clip length", selection: $state.videoDurationSeconds) {
      ForEach(limits.pickerSeconds, id: \.self) { sec in
        Text("\(sec)s").tag(sec)
      }
    }
    .onChange(of: state.selectedVideoModelId) { newId in
      let lim = VideoDurationCatalog.limits(for: newId ?? "")
      state.videoDurationSeconds = lim.clamp(state.videoDurationSeconds)
    }
    .accessibilityLabel("Clip length in seconds")
    Text("\(limits.min)–\(limits.max)s for this model (default \(limits.defaultSeconds)s). Longer clips take longer to generate.")
      .font(.caption2)
      .foregroundStyle(.secondary)
  }

  private var videoFooter: String {
    let mid = state.selectedVideoModelId ?? ""
    let lim = VideoDurationCatalog.limits(for: mid)
    if mid.hasPrefix("minimax/hailuo") {
      return "Hailuo is image-to-video only: add a photo above. Duration \(lim.min)–\(lim.max)s. For text-only use Veo or Seedance Fast."
    }
    if mid.hasPrefix("xai/grok-imagine-video") {
      return "Grok video: duration \(lim.min)–\(lim.max)s. ZDR upload path on plane 0.4.14+. Prefer Veo / Seedance Fast if playback fails."
    }
    return "Veo and Seedance Fast are most reliable. Full Seedance may take up to ~3 min. "
      + "Jobs run on the plane; safe to lock while polling. Grok uses signed play-proxy media."
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

/// Sheet payload for UIActivityViewController.
private struct SharePayload: Identifiable {
  let id = UUID()
  let items: [Any]
}

#if canImport(UIKit)
private struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
private struct ActivityView: View {
  let items: [Any]
  var body: some View { Text("Share unavailable") }
}
#endif

#Preview {
  NavigationStack {
    MediaGenerateView(kind: .image)
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
