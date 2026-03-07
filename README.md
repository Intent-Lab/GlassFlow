# GlassFlow

<p align="center">
  <img src="glassflow.png" alt="GlassFlow - Face-to-Face Transcription" width="600">
</p>

Real-time transcription for Meta Ray-Ban smart glasses. Captures audio from your glasses (or phone mic) and transcribes it live using Deepgram's streaming API, with speaker diarization and partial results.

**Supported platforms:** iOS (iPhone) and Android (Pixel, Samsung, etc.)

## What It Does

Start streaming from your glasses, tap the **Scribe** button, and get a live transcript:

- Real-time speech-to-text via Deepgram Nova-3 (streaming WebSocket)
- Speaker diarization -- labels who is speaking (S1, S2, ...)
- Partial results update in real-time as words are spoken
- Final results with punctuation and smart formatting
- Works with glasses mic or phone mic (iPhone/Phone mode)

Also includes:

- **Gemini Live** -- real-time voice + vision AI assistant (optional)
- **WebRTC streaming** -- share your glasses POV live to a browser viewer
- **Phone mode** -- test without glasses using your phone camera + mic

## How It Works

```
Meta Ray-Ban Glasses (or phone mic)
       |
       | PCM audio (16kHz mono)
       v
iOS / Android App (this project)
       |
       | PCM Int16 stream (100ms chunks)
       v
Deepgram Nova-3 (WebSocket)
       |
       |-- Partial transcripts --> App --> Live UI
       |-- Final transcripts ----> App --> Scrolling panel
       |-- Speaker labels -------> App --> S1, S2, S3...
       v
  Real-time transcript display
```

---

## Quick Start (iOS)

### 1. Clone and open

```bash
git clone https://github.com/sseanliu/GlassFlow.git
cd GlassFlow/samples/CameraAccess
open CameraAccess.xcodeproj
```

### 2. Add your secrets

```bash
cp CameraAccess/Secrets.swift.example CameraAccess/Secrets.swift
```

Edit `Secrets.swift` with your API keys:
- [Deepgram API key](https://deepgram.com) (required for transcription)
- [Gemini API key](https://aistudio.google.com/apikey) (optional, for AI assistant)

### 3. Build and run

Select your iPhone as the target device and hit Run (Cmd+R).

### 4. Try it out

**Without glasses (iPhone mode):**
1. Tap **"Start on iPhone"**
2. Tap the **Scribe** button to start transcribing
3. Speak -- the transcript appears in real-time

**With Meta Ray-Ban glasses:**

First, enable Developer Mode in the Meta AI app:

1. Open the **Meta AI** app on your iPhone
2. Go to **Settings** (gear icon, bottom left)
3. Tap **App Info**
4. Tap the **App version** number **5 times** -- this unlocks Developer Mode
5. Go back to Settings -- you'll now see a **Developer Mode** toggle. Turn it on.

Then in GlassFlow:
1. Tap **"Start Streaming"** in the app
2. Tap the **Scribe** button for live transcription

---

## Quick Start (Android)

### 1. Clone and open

```bash
git clone https://github.com/sseanliu/GlassFlow.git
```

Open `samples/CameraAccessAndroid/` in Android Studio.

### 2. Configure GitHub Packages (DAT SDK)

The Meta DAT Android SDK is distributed via GitHub Packages. You need a GitHub Personal Access Token with `read:packages` scope.

1. Go to [GitHub > Settings > Developer Settings > Personal Access Tokens](https://github.com/settings/tokens) and create a **classic** token with `read:packages` scope
2. In `samples/CameraAccessAndroid/local.properties`, add:

```properties
github_token=YOUR_GITHUB_TOKEN
```

### 3. Add your secrets

```bash
cd samples/CameraAccessAndroid/app/src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/
cp Secrets.kt.example Secrets.kt
```

Edit `Secrets.kt` with your [Deepgram API key](https://deepgram.com) (required) and optional [Gemini API key](https://aistudio.google.com/apikey).

### 4. Build and run

1. Let Gradle sync in Android Studio
2. Select your Android phone as the target device
3. Click Run (Shift+F10)

### 5. Try it out

**Without glasses (Phone mode):**
1. Tap **"Start on Phone"**
2. Tap the **Scribe** button to start transcribing
3. Speak -- the transcript appears in real-time

**With Meta Ray-Ban glasses:**

Enable Developer Mode in the Meta AI app (same steps as iOS above), then:
1. Tap **"Start Streaming"** in the app
2. Tap the **Scribe** button for live transcription

---

## Architecture

### Key Files (iOS)

All source code is in `samples/CameraAccess/CameraAccess/`:

| File | Purpose |
|------|---------|
| `Transcription/DeepgramService.swift` | WebSocket streaming client for Deepgram Nova-3 |
| `Transcription/TranscriptionViewModel.swift` | Session lifecycle, partial/final segment management |
| `Transcription/TranscriptionView.swift` | Live scrolling transcript panel with speaker labels |
| `Gemini/AudioManager.swift` | Mic capture (PCM 16kHz) + audio playback (PCM 24kHz) |
| `Gemini/GeminiConfig.swift` | API keys, model config |
| `Gemini/GeminiLiveService.swift` | WebSocket client for Gemini Live API |
| `Gemini/GeminiSessionViewModel.swift` | Gemini session lifecycle |
| `iPhone/IPhoneCameraManager.swift` | AVCaptureSession wrapper for iPhone camera mode |
| `WebRTC/WebRTCClient.swift` | WebRTC peer connection + SDP negotiation |

### Transcription Pipeline

- **Input**: Glasses mic or phone mic -> AudioManager (PCM Int16, 16kHz mono, 100ms chunks)
- **Streaming**: PCM chunks sent over WebSocket to Deepgram in real-time
- **Output**: Partial transcripts update live, final transcripts with punctuation and speaker labels
- **Diarization**: Deepgram identifies speakers (S1, S2, ...) automatically

### Audio Modes

- **iPhone mode**: `.voiceChat` audio session for echo cancellation (mic + speaker co-located)
- **Glasses mode**: `.videoChat` audio session with Bluetooth HFP (mic is on glasses, speaker is on phone)

---

## Requirements

### iOS
- iOS 17.0+
- Xcode 15.0+
- Deepgram API key ([get one free](https://deepgram.com))
- Meta Ray-Ban glasses (optional -- use iPhone mode for testing)
- Gemini API key (optional, for AI assistant)

### Android
- Android 14+ (API 34+)
- Android Studio Ladybug or newer
- GitHub account with `read:packages` token (for DAT SDK)
- Deepgram API key ([get one free](https://deepgram.com))
- Meta Ray-Ban glasses (optional -- use Phone mode for testing)
- Gemini API key (optional, for AI assistant)

---

## Troubleshooting

**Transcript not appearing** -- Check that your Deepgram API key is configured in Settings or Secrets.swift. Make sure microphone permission is granted.

**"Deepgram API key not configured"** -- Add your key in the in-app Settings screen (Deepgram section) or in Secrets.swift.

**Echo/feedback in iPhone mode** -- The app uses `.voiceChat` audio session for echo cancellation. Try turning down the volume.

**Gradle sync fails with 401 Unauthorized** (Android) -- Your GitHub token is missing or doesn't have `read:packages` scope. Check `local.properties`. Generate a new token at [github.com/settings/tokens](https://github.com/settings/tokens).

For DAT SDK issues, see the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or the [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

## License

This source code is licensed under the license found in the [LICENSE](LICENSE) file in the root directory of this source tree.
