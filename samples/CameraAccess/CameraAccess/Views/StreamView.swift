/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for GlassFlow real-time transcription.
// Clean white background with transcript as primary content.
// Controls use .ultraThinMaterial for a Liquid Glass aesthetic.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel
  @ObservedObject var transcriptionVM: TranscriptionViewModel

  var body: some View {
    VStack(spacing: 0) {
      TopBar(
        transcriptionVM: transcriptionVM,
        geminiVM: geminiVM,
        webrtcVM: webrtcVM
      )

      Divider()

      TranscriptionContentView(viewModel: transcriptionVM)

      Divider()

      ControlsView(
        viewModel: viewModel,
        geminiVM: geminiVM,
        webrtcVM: webrtcVM,
        transcriptionVM: transcriptionVM
      )
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
    }
    .background(Color(.systemBackground))
    .onDisappear {
      Task {
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession()
        }
        if geminiVM.isGeminiActive {
          geminiVM.stopSession()
        }
        if webrtcVM.isActive {
          webrtcVM.stopSession()
        }
        if transcriptionVM.isActive {
          transcriptionVM.stopSession()
        }
      }
    }
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
    .alert("AI Assistant", isPresented: Binding(
      get: { geminiVM.errorMessage != nil },
      set: { if !$0 { geminiVM.errorMessage = nil } }
    )) {
      Button("OK") { geminiVM.errorMessage = nil }
    } message: {
      Text(geminiVM.errorMessage ?? "")
    }
    .alert("Live Stream", isPresented: Binding(
      get: { webrtcVM.errorMessage != nil },
      set: { if !$0 { webrtcVM.errorMessage = nil } }
    )) {
      Button("OK") { webrtcVM.errorMessage = nil }
    } message: {
      Text(webrtcVM.errorMessage ?? "")
    }
    .alert("Transcription", isPresented: Binding(
      get: { transcriptionVM.errorMessage != nil },
      set: { if !$0 { transcriptionVM.errorMessage = nil } }
    )) {
      Button("OK") { transcriptionVM.errorMessage = nil }
    } message: {
      Text(transcriptionVM.errorMessage ?? "")
    }
  }
}

// MARK: - Top Bar

struct TopBar: View {
  @ObservedObject var transcriptionVM: TranscriptionViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel

  var body: some View {
    HStack {
      Text("GlassFlow")
        .font(.title2.bold())
        .foregroundColor(.primary)

      Spacer()

      HStack(spacing: 8) {
        if transcriptionVM.isActive {
          StatusBadge(color: statusColor, text: statusText)
        }
        if geminiVM.isGeminiActive {
          StatusBadge(color: .green, text: "AI")
        }
        if webrtcVM.isActive {
          StatusBadge(color: .blue, text: "Live")
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private var statusColor: Color {
    switch transcriptionVM.connectionState {
    case .connected: return .green
    case .connecting: return .orange
    case .disconnected: return .gray
    case .error: return .red
    }
  }

  private var statusText: String {
    switch transcriptionVM.connectionState {
    case .connected: return "Transcribing"
    case .connecting: return "Connecting..."
    case .disconnected: return "Off"
    case .error: return "Error"
    }
  }
}

struct StatusBadge: View {
  let color: Color
  let text: String

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
      Text(text)
        .font(.caption.weight(.semibold))
        .foregroundColor(.primary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(.secondarySystemFill))
    .clipShape(Capsule())
  }
}

// MARK: - Controls

struct ControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel
  @ObservedObject var transcriptionVM: TranscriptionViewModel

  var body: some View {
    HStack(spacing: 12) {
      Button {
        Task { await viewModel.stopSession() }
      } label: {
        Text("Stop")
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.white)
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
          .background(Color.red)
          .clipShape(Capsule())
      }

      Spacer()

      ControlPill(
        icon: transcriptionVM.isActive ? "text.bubble.fill" : "text.bubble",
        label: "Scribe",
        isActive: transcriptionVM.isActive,
        isDisabled: geminiVM.isGeminiActive || webrtcVM.isActive
      ) {
        Task {
          if transcriptionVM.isActive {
            transcriptionVM.stopSession()
          } else {
            await transcriptionVM.startSession()
          }
        }
      }

      ControlPill(
        icon: geminiVM.isGeminiActive ? "waveform.circle.fill" : "waveform.circle",
        label: "AI",
        isActive: geminiVM.isGeminiActive,
        isDisabled: webrtcVM.isActive || transcriptionVM.isActive
      ) {
        Task {
          if geminiVM.isGeminiActive {
            geminiVM.stopSession()
          } else {
            await geminiVM.startSession()
          }
        }
      }

      ControlPill(
        icon: webrtcVM.isActive
          ? "antenna.radiowaves.left.and.right.circle.fill"
          : "antenna.radiowaves.left.and.right.circle",
        label: "Live",
        isActive: webrtcVM.isActive,
        isDisabled: geminiVM.isGeminiActive || transcriptionVM.isActive
      ) {
        Task {
          if webrtcVM.isActive {
            webrtcVM.stopSession()
          } else {
            await webrtcVM.startSession()
          }
        }
      }
    }
  }
}

struct ControlPill: View {
  let icon: String
  let label: String
  let isActive: Bool
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.subheadline)
        Text(label)
          .font(.subheadline.weight(.semibold))
      }
      .foregroundColor(isActive ? .white : .primary)
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background {
        if isActive {
          Capsule().fill(Color.primary)
        } else {
          Capsule().fill(Color(.secondarySystemFill))
        }
      }
      .clipShape(Capsule())
    }
    .opacity(isDisabled ? 0.5 : 1.0)
    .disabled(isDisabled)
  }
}

// MARK: - Color Extension

extension Color {
  init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r = Double((int >> 16) & 0xFF) / 255.0
    let g = Double((int >> 8) & 0xFF) / 255.0
    let b = Double(int & 0xFF) / 255.0
    self.init(red: r, green: g, blue: b)
  }
}
