package com.meta.wearable.dat.externalsampleapps.cameraaccess.gemini

import org.json.JSONArray
import org.json.JSONObject

// MARK: - Gemini Tool Call (parsed from server JSON)

data class GeminiFunctionCall(
    val id: String,
    val name: String,
    val args: Map<String, Any>
)

data class GeminiToolCall(
    val functionCalls: List<GeminiFunctionCall>
) {
    companion object {
        fun parse(json: JSONObject): GeminiToolCall? {
            val toolCall = json.optJSONObject("toolCall") ?: return null
            val calls = toolCall.optJSONArray("functionCalls") ?: return null

            val parsed = mutableListOf<GeminiFunctionCall>()
            for (i in 0 until calls.length()) {
                val call = calls.getJSONObject(i)
                val id = call.optString("id", "")
                val name = call.optString("name", "")
                if (id.isEmpty() || name.isEmpty()) continue

                val argsObj = call.optJSONObject("args")
                val args = mutableMapOf<String, Any>()
                if (argsObj != null) {
                    for (key in argsObj.keys()) {
                        args[key] = argsObj.get(key)
                    }
                }
                parsed.add(GeminiFunctionCall(id = id, name = name, args = args))
            }
            return if (parsed.isNotEmpty()) GeminiToolCall(parsed) else null
        }
    }
}

// MARK: - Gemini Tool Call Cancellation

data class GeminiToolCallCancellation(
    val ids: List<String>
) {
    companion object {
        fun parse(json: JSONObject): GeminiToolCallCancellation? {
            val cancellation = json.optJSONObject("toolCallCancellation") ?: return null
            val idsArray = cancellation.optJSONArray("ids") ?: return null
            val ids = mutableListOf<String>()
            for (i in 0 until idsArray.length()) {
                ids.add(idsArray.getString(i))
            }
            return if (ids.isNotEmpty()) GeminiToolCallCancellation(ids) else null
        }
    }
}

// MARK: - Tool Result

sealed class ToolResult {
    data class Success(val result: String) : ToolResult()
    data class Failure(val error: String) : ToolResult()

    fun toResponseValue(): JSONObject {
        return when (this) {
            is Success -> JSONObject().put("result", result)
            is Failure -> JSONObject().put("error", error)
        }
    }
}

// MARK: - Tool Declarations (for Gemini setup message)

object ToolDeclarations {
    fun allDeclarations(): JSONArray {
        return JSONArray().apply {
            put(execute)
            put(capturePhoto)
        }
    }

    val execute: JSONObject
        get() = JSONObject().apply {
            put("name", "execute")
            put("description", "Your only way to take action. You have no memory, storage, or ability to do anything on your own -- use this tool for everything: sending messages, searching the web, adding to lists, setting reminders, creating notes, research, drafts, scheduling, smart home control, app interactions, or any request that goes beyond answering a question. When in doubt, use this tool.")
            put("parameters", JSONObject().apply {
                put("type", "object")
                put("properties", JSONObject().apply {
                    put("task", JSONObject().apply {
                        put("type", "string")
                        put("description", "Clear, detailed description of what to do. Include all relevant context: names, content, platforms, quantities, etc.")
                    })
                })
                put("required", JSONArray().put("task"))
            })
        }

    val capturePhoto: JSONObject
        get() = JSONObject().apply {
            put("name", "capture_photo")
            put("description", "Capture and save the current camera frame as a photo. Use when the user asks to take a photo, capture what they see, save a picture, or snap a photo.")
            put("parameters", JSONObject().apply {
                put("type", "object")
                put("properties", JSONObject().apply {
                    put("description", JSONObject().apply {
                        put("type", "string")
                        put("description", "Brief description of what is in the photo")
                    })
                })
                put("required", JSONArray())
            })
        }
}
