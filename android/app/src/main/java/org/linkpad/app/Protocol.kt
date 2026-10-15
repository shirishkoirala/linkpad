package org.linkpad.app

import kotlinx.serialization.json.*

object Protocol {
    const val POINTER = "pointer.v1"
    const val KEY = "key.v1"
    private fun envelope(type: String, body: JsonObjectBuilder.() -> Unit = {}): String =
        buildJsonObject { put("version", 1); put("type", type); body() }.toString()
    fun hello(token: String): String = envelope(if (token.isBlank()) "hello" else "pair") {
        if (token.isNotBlank()) put("token", token)
        putJsonArray("capabilities") { add(POINTER); add(KEY) }
    }
    fun heartbeat(): String = envelope("hello")
    fun pointer(dx: Int = 0, dy: Int = 0, button: String = ""): String {
        require(dx in -500..500 && dy in -500..500)
        require(button in listOf("", "left", "right"))
        return envelope("pointer") { put("dx", dx); put("dy", dy); if (button.isNotEmpty()) put("button", button) }
    }
    fun key(name: String): String {
        require(name in listOf("up", "down", "left", "right"))
        return envelope("key") { put("key", name) }
    }
    fun parse(text: String): JsonObject {
        require(text.length <= 4096) { "Message too large" }
        val obj = Json.parseToJsonElement(text).jsonObject
        require(obj["version"]?.jsonPrimitive?.int == 1) { "Unsupported protocol" }
        return obj
    }
}
