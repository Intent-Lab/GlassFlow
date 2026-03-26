package com.meta.wearable.dat.externalsampleapps.cameraaccess.gemini

import android.app.Application
import android.graphics.Bitmap
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.meta.wearable.dat.externalsampleapps.cameraaccess.gallery.CapturedPhoto
import com.meta.wearable.dat.externalsampleapps.cameraaccess.gallery.PhotoCaptureStore
import com.meta.wearable.dat.externalsampleapps.cameraaccess.stream.StreamingMode
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

data class GeminiUiState(
    val isGeminiActive: Boolean = false,
    val connectionState: GeminiConnectionState = GeminiConnectionState.Disconnected,
    val isModelSpeaking: Boolean = false,
    val errorMessage: String? = null,
    val userTranscript: String = "",
    val aiTranscript: String = "",
)

class GeminiSessionViewModel(application: Application) : AndroidViewModel(application) {
    companion object {
        private const val TAG = "GeminiSessionVM"
    }

    private val _uiState = MutableStateFlow(GeminiUiState())
    val uiState: StateFlow<GeminiUiState> = _uiState.asStateFlow()

    private val _captureEvent = MutableStateFlow<CapturedPhoto?>(null)
    val captureEvent: StateFlow<CapturedPhoto?> = _captureEvent.asStateFlow()

    private val geminiService = GeminiLiveService()
    private val audioManager = AudioManager()
    private var lastVideoFrameTime: Long = 0
    private var latestFrame: Bitmap? = null
    private var stateObservationJob: Job? = null

    var streamingMode: StreamingMode = StreamingMode.GLASSES

    fun startSession() {
        if (_uiState.value.isGeminiActive) return

        if (!GeminiConfig.isConfigured) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "Gemini API key not configured. Open Settings and add your key from https://aistudio.google.com/apikey"
            )
            return
        }

        _uiState.value = _uiState.value.copy(isGeminiActive = true)
        RemoteLogger.log("session:start")

        // Wire audio callbacks
        audioManager.onAudioCaptured = lambda@{ data ->
            // Phone mode: mute mic while model speaks to prevent echo
            if (streamingMode == StreamingMode.PHONE && geminiService.isModelSpeaking.value) return@lambda
            geminiService.sendAudio(data)
        }

        geminiService.onAudioReceived = { data ->
            audioManager.playAudio(data)
        }

        geminiService.onInterrupted = {
            audioManager.stopPlayback()
        }

        geminiService.onTurnComplete = {
            // Log finalized transcripts before clearing
            val userText = _uiState.value.userTranscript
            val aiText = _uiState.value.aiTranscript
            if (userText.isNotEmpty()) {
                RemoteLogger.log("voice:user", mapOf("text" to userText))
            }
            if (aiText.isNotEmpty()) {
                RemoteLogger.log("voice:ai", mapOf("text" to aiText))
            }
            _uiState.value = _uiState.value.copy(userTranscript = "")
        }

        geminiService.onInputTranscription = { text ->
            _uiState.value = _uiState.value.copy(
                userTranscript = _uiState.value.userTranscript + text,
                aiTranscript = ""
            )
        }

        geminiService.onOutputTranscription = { text ->
            _uiState.value = _uiState.value.copy(
                aiTranscript = _uiState.value.aiTranscript + text
            )
        }

        geminiService.onDisconnected = { reason ->
            if (_uiState.value.isGeminiActive) {
                stopSession()
                _uiState.value = _uiState.value.copy(
                    errorMessage = "Connection lost: ${reason ?: "Unknown error"}"
                )
            }
        }

        // Wire tool call handling
        geminiService.onToolCall = { toolCall ->
            for (call in toolCall.functionCalls) {
                Log.d(TAG, "Tool call: ${call.name} (id: ${call.id}) args: ${call.args}")
                when (call.name) {
                    "capture_photo" -> handleCapturePhoto(call)
                    else -> {
                        // Other tools (execute) — not configured on Android yet
                        val response = buildToolResponse(
                            call.id, call.name,
                            ToolResult.Failure("Tool '${call.name}' is not configured on Android")
                        )
                        geminiService.sendToolResponse(response)
                    }
                }
            }
        }

        geminiService.onToolCallCancellation = { cancellation ->
            Log.d(TAG, "Tool call cancellation: ${cancellation.ids}")
        }

        // Load gallery
        PhotoCaptureStore.loadPhotos(getApplication())

        viewModelScope.launch {
            // Observe service state
            stateObservationJob = viewModelScope.launch {
                while (isActive) {
                    delay(100)
                    _uiState.value = _uiState.value.copy(
                        connectionState = geminiService.connectionState.value,
                        isModelSpeaking = geminiService.isModelSpeaking.value,
                    )
                }
            }

            // Connect to Gemini
            geminiService.connect { setupOk ->
                if (!setupOk) {
                    val msg = when (val state = geminiService.connectionState.value) {
                        is GeminiConnectionState.Error -> state.message
                        else -> "Failed to connect to Gemini"
                    }
                    _uiState.value = _uiState.value.copy(errorMessage = msg)
                    geminiService.disconnect()
                    stateObservationJob?.cancel()
                    _uiState.value = _uiState.value.copy(
                        isGeminiActive = false,
                        connectionState = GeminiConnectionState.Disconnected
                    )
                    return@connect
                }

                // Start mic capture
                try {
                    audioManager.startCapture()
                } catch (e: Exception) {
                    _uiState.value = _uiState.value.copy(
                        errorMessage = "Mic capture failed: ${e.message}"
                    )
                    geminiService.disconnect()
                    stateObservationJob?.cancel()
                    _uiState.value = _uiState.value.copy(
                        isGeminiActive = false,
                        connectionState = GeminiConnectionState.Disconnected
                    )
                }
            }
        }
    }

    fun stopSession() {
        RemoteLogger.log("session:end")
        audioManager.stopCapture()
        geminiService.disconnect()
        stateObservationJob?.cancel()
        stateObservationJob = null
        _uiState.value = GeminiUiState()
    }

    fun sendVideoFrameIfThrottled(bitmap: Bitmap) {
        // Always keep latest frame for capture_photo
        latestFrame = bitmap
        if (!_uiState.value.isGeminiActive) return
        if (_uiState.value.connectionState != GeminiConnectionState.Ready) return
        val now = System.currentTimeMillis()
        if (now - lastVideoFrameTime < GeminiConfig.VIDEO_FRAME_INTERVAL_MS) return
        lastVideoFrameTime = now
        geminiService.sendVideoFrame(bitmap)
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    private fun handleCapturePhoto(call: GeminiFunctionCall) {
        val description = call.args["description"]?.toString()
        val frame = latestFrame
        val ctx = getApplication<Application>()

        val result: ToolResult
        if (frame != null) {
            val photo = PhotoCaptureStore.saveFrame(ctx, frame, description)
            if (photo != null) {
                _captureEvent.value = photo
                result = ToolResult.Success("Photo captured and saved: ${photo.filename}")
            } else {
                result = ToolResult.Failure("Failed to save photo")
            }
        } else {
            result = ToolResult.Failure("No camera frame available to capture")
        }

        val response = buildToolResponse(call.id, call.name, result)
        geminiService.sendToolResponse(response)
        Log.d(TAG, "capture_photo result: $result")
    }

    private fun buildToolResponse(callId: String, name: String, result: ToolResult): JSONObject {
        return JSONObject().apply {
            put("toolResponse", JSONObject().apply {
                put("functionResponses", JSONArray().apply {
                    put(JSONObject().apply {
                        put("id", callId)
                        put("name", name)
                        put("response", result.toResponseValue())
                    })
                })
            })
        }
    }

    override fun onCleared() {
        super.onCleared()
        stopSession()
    }
}
