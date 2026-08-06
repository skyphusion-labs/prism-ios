import SwiftUI
import PrismKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Control-plane TTS + STT (`POST /v1/audio/speech` and `/v1/audio/transcriptions`).
struct SpeechGenerateView: View {
  enum Mode: String, CaseIterable, Identifiable {
    case speak
    case transcribe
    var id: String { rawValue }
    var title: String {
      switch self {
      case .speak: return "Speak"
      case .transcribe: return "Transcribe"
      }
    }
  }

  @EnvironmentObject private var state: AppState
  @StateObject private var recorder = AudioRecorder()
  @State private var mode: Mode = .speak
  @State private var sharePayload: SharePayload?
  @State private var showImporter = false

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

      Picker("Mode", selection: $mode) {
        ForEach(Mode.allCases) { m in
          Text(m.title).tag(m)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .padding(.vertical, 8)
      .accessibilityLabel("Audio mode")

      Form {
        if !state.canUseMediaDoors {
          Section {
            Text("Control plane + device key required. Enroll in Settings.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        switch mode {
        case .speak:
          ttsSections
        case .transcribe:
          sttSections
        }
      }
    }
    .navigationTitle("Audio")
    .fileImporter(
      isPresented: $showImporter,
      allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
          let mime = mimeFor(url: url)
          state.setSttAudioData(data, mime: mime, label: url.lastPathComponent)
        } else {
          state.sttError = "Could not read that audio file."
        }
      case .failure(let err):
        state.sttError = err.localizedDescription
      }
    }
    .sheet(item: $sharePayload) { payload in
      ActivityView(items: payload.items)
    }
  }

  // MARK: - TTS

  @ViewBuilder
  private var ttsSections: some View {
    Section {
      modelSearchField
      Picker("Model", selection: Binding(
        get: { state.selectedSpeechModelId ?? state.speechModels.first?.model ?? "" },
        set: { state.selectSpeechModel($0) }
      )) {
        ForEach(state.speechModels) { m in
          Text(shortLabel(m)).tag(m.model)
        }
      }
      if let id = state.selectedSpeechModelId ?? state.speechModels.first?.model {
        Text(id).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
      }
      if state.speechModels.isEmpty, state.canUseMediaDoors {
        Text("No TTS models match. Clear search or refresh models.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    } header: {
      Text("TTS model")
    }

    Section {
      TextField("Text to speak", text: $state.speechText, axis: .vertical)
        .lineLimit(3...12)
        .font(.body)
        .accessibilityLabel("Text to speak")
      if let preview = state.speechSpendPreview {
        Text(preview).font(.footnote).foregroundStyle(.secondary)
      }
      if state.speechBusy {
        HStack {
          ProgressView()
          Text(state.speechStatus ?? "Synthesizing…").font(.footnote).foregroundStyle(.secondary)
        }
        Button(role: .destructive) { state.cancelSpeech() } label: {
          Text("Cancel").frame(maxWidth: .infinity).frame(minHeight: 44)
        }
      } else {
        Button { state.generateSpeech() } label: {
          Text("Generate speech").frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .disabled(!state.canUseMediaDoors || state.speechModels.isEmpty
          || state.speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    } header: {
      Text("Input")
    } footer: {
      Text("Aura-2 is billed per 1k characters; MeloTTS per audio minute. Audio plays when ready.")
    }

    if let status = state.speechStatus {
      Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
    }
    if let err = state.speechError {
      Section { Text(err).font(.footnote).foregroundStyle(.red) }
    }
    if state.lastSpeechData != nil {
      Section {
        Button { state.playLastSpeech() } label: {
          Label("Play", systemImage: "play.circle.fill")
            .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
        }
        #if canImport(UIKit)
        Button {
          if let data = state.lastSpeechData {
            let name = "prism-speech.\(state.lastSpeechFormat)"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? data.write(to: url)
            sharePayload = SharePayload(items: [url])
          }
        } label: {
          Label("Share audio", systemImage: "square.and.arrow.up")
        }
        #endif
        if let model = state.lastSpeechModel {
          Text(model).font(.caption2).foregroundStyle(.secondary)
        }
      } header: {
        Text("Result")
      }
    }
  }

  // MARK: - STT

  @ViewBuilder
  private var sttSections: some View {
    Section {
      modelSearchField
      Picker("Model", selection: Binding(
        get: { state.selectedSttModelId ?? state.sttModels.first?.model ?? "" },
        set: { state.selectSttModel($0) }
      )) {
        ForEach(state.sttModels) { m in
          Text(shortLabel(m)).tag(m.model)
        }
      }
      if let id = state.selectedSttModelId ?? state.sttModels.first?.model {
        Text(id).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
      }
      if state.sttModels.isEmpty, state.canUseMediaDoors {
        Text("No STT models match. Clear search or refresh models.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    } header: {
      Text("STT model")
    }

    Section {
      if recorder.isRecording {
        HStack {
          Image(systemName: "mic.fill").foregroundStyle(.red)
          Text("Recording \(recorder.elapsedSeconds)s…")
            .font(.footnote.monospacedDigit())
          Spacer()
        }
        .accessibilityLabel("Recording, \(recorder.elapsedSeconds) seconds")
        Button(role: .destructive) {
          if let cap = recorder.stop() {
            state.setSttAudioData(cap.data, mime: "audio/mp4", label: "recording.m4a")
          }
        } label: {
          Text("Stop and use recording")
            .frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        Button("Cancel recording") {
          recorder.cancel()
        }
      } else {
        Button {
          Task {
            if !recorder.hasPermission {
              let ok = await recorder.requestPermission()
              if !ok {
                state.sttError = "Microphone permission denied. Enable it in Settings."
                return
              }
            }
            do {
              try recorder.start()
            } catch {
              state.sttError = prismUserFacingError(error)
            }
          }
        } label: {
          Label("Record microphone", systemImage: "mic")
            .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
        }
        .disabled(!state.canUseMediaDoors)
        Button {
          showImporter = true
        } label: {
          Label("Import audio file", systemImage: "folder")
            .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
        }
      }

      if !state.sttAudioLabel.isEmpty {
        Text(state.sttAudioLabel).font(.caption).foregroundStyle(.secondary)
        Button("Clear audio", role: .destructive) {
          state.clearSttAudio()
        }
      }

      if let preview = state.sttSpendPreview {
        Text(preview).font(.footnote).foregroundStyle(.secondary)
      }

      if state.sttBusy {
        HStack {
          ProgressView()
          Text(state.sttStatus ?? "Transcribing…").font(.footnote).foregroundStyle(.secondary)
        }
        Button(role: .destructive) { state.cancelStt() } label: {
          Text("Cancel").frame(maxWidth: .infinity).frame(minHeight: 44)
        }
      } else {
        Button { state.transcribeAudio() } label: {
          Text("Transcribe").frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .disabled(!state.canUseMediaDoors || state.sttModels.isEmpty
          || state.sttAudioPayload.isEmpty)
      }
    } header: {
      Text("Audio")
    } footer: {
      Text("Whisper and Nova-3 STT bill per audio minute (plane floors at 1). Prefer short clips.")
    }

    if let status = state.sttStatus {
      Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
    }
    if let err = state.sttError ?? recorder.errorMessage {
      Section { Text(err).font(.footnote).foregroundStyle(.red) }
    }
    if let text = state.lastTranscript {
      Section {
        Text(text)
          .font(.body)
          .textSelection(.enabled)
        #if canImport(UIKit)
        Button {
          UIPasteboard.general.string = text
          Haptics.light()
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        #endif
        Button {
          state.useTranscriptAsChatDraft()
        } label: {
          Label("Use as chat draft", systemImage: "bubble.left")
        }
        Button {
          state.useTranscriptAsSpeech()
          mode = .speak
        } label: {
          Label("Speak this text", systemImage: "waveform")
        }
        if let model = state.lastSttModel {
          Text(model).font(.caption2).foregroundStyle(.secondary)
        }
      } header: {
        Text("Transcript")
      }
    }
  }

  private var modelSearchField: some View {
    Group {
      if state.backend == .controlPlane {
        TextField("Search models", text: $state.modelSearch)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
    }
  }

  private func shortLabel(_ m: ModelEntry) -> String {
    var parts = [m.label ?? m.model]
    if let p = m.priceLabel { parts.append(p) }
    return parts.joined(separator: " · ")
  }

  private func mimeFor(url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "mp3": return "audio/mpeg"
    case "wav": return "audio/wav"
    case "m4a", "mp4", "aac": return "audio/mp4"
    case "webm": return "audio/webm"
    case "ogg": return "audio/ogg"
    default: return "audio/mp4"
    }
  }
}

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
#endif

#Preview {
  NavigationStack {
    SpeechGenerateView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
