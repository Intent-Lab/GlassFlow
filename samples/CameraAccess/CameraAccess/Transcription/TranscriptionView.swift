import SwiftUI

// MARK: - Main Transcript Content (fills the screen)

struct TranscriptionContentView: View {
  @ObservedObject var viewModel: TranscriptionViewModel

  var body: some View {
    Group {
      if !viewModel.isActive && viewModel.segments.isEmpty {
        emptyState
      } else if viewModel.segments.isEmpty && viewModel.isActive {
        listeningState
      } else {
        transcriptList
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "text.bubble")
        .font(.title)
        .foregroundColor(.secondary)
      Text("Tap Scribe to start transcribing")
        .font(.body)
        .foregroundColor(.secondary)
    }
  }

  private var listeningState: some View {
    VStack(spacing: 10) {
      Image(systemName: "waveform")
        .font(.title)
        .foregroundColor(.secondary)
      Text("Listening...")
        .font(.body.weight(.medium))
        .foregroundColor(.secondary)
    }
  }

  private var transcriptList: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 20) {
          ForEach(viewModel.segments) { segment in
            SegmentRow(segment: segment)
              .id(segment.id)
          }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 16)
      }
      .onChange(of: viewModel.segments.count) { _ in
        scrollToBottom(proxy)
      }
      .onChange(of: viewModel.currentPartialText) { _ in
        scrollToBottom(proxy)
      }
    }
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    if let lastId = viewModel.segments.last?.id {
      withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(lastId, anchor: .bottom)
      }
    }
  }
}

// MARK: - Segment Row

struct SegmentRow: View {
  let segment: TranscriptSegment

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        if let speaker = segment.speaker {
          Text("Speaker \(speaker + 1)")
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
        }
        Text(timeString(segment.timestamp))
          .font(.caption2.monospaced())
          .foregroundColor(.secondary)
      }

      Text(segment.text)
        .font(.body)
        .foregroundColor(segment.isFinal ? .primary : .secondary)
        .fixedSize(horizontal: false, vertical: true)
        .lineSpacing(4)
    }
  }

  private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
  }
}

// MARK: - Legacy overlay (kept for Gemini transcript)

struct TranscriptionOverlayView: View {
  @ObservedObject var viewModel: TranscriptionViewModel

  var body: some View {
    TranscriptionContentView(viewModel: viewModel)
  }
}
