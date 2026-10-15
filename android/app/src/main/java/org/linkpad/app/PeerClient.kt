package org.linkpad.app

import android.os.Handler
import android.os.Looper
import kotlinx.serialization.json.*
import okhttp3.*
import okio.ByteString
import java.util.concurrent.TimeUnit

class PeerClient(private val status: (String, Boolean) -> Unit, private val paired: (String, String) -> Unit, private val onKeys: (Boolean) -> Unit = {}) {
    private val main = Handler(Looper.getMainLooper())
    private var socket: WebSocket? = null
    private var http: OkHttpClient? = null
    private var ready = false
    private var keyReady = false
    private var handshaken = false
    private var pending = false
    private var lastSend = 0L
    private var generation = 0
    private val timeout = Runnable { close(); status("Peer response timed out", false) }
    private val heartbeat = object : Runnable {
        override fun run() {
            if (handshaken && !pending) {
                pending = socket?.send(Protocol.heartbeat()) == true
                if (pending) main.postDelayed(timeout, 5000)
            }
            main.postDelayed(this, 30000)
        }
    }
    fun connect(address: String, pin: String, token: String) {
        close()
        val current = generation
        try {
            require(android.os.Build.VERSION.SDK_INT >= 29) { "TLS 1.3 requires Android 10 or newer for this slice" }
            val uri = java.net.URI(address)
            require(uri.scheme == "wss" && uri.host != null && uri.path == "/ws" && uri.userInfo == null && uri.query == null && uri.fragment == null) { "Use wss://HOST:4747/ws" }
            val (context, trust) = PeerIdentity.context(pin.trim())
            http = OkHttpClient.Builder().sslSocketFactory(context.socketFactory, trust)
                // Device identity is the exact certificate pin, independent of DNS name.
                .hostnameVerifier { _, _ -> true }
                .connectionSpecs(listOf(ConnectionSpec.Builder(ConnectionSpec.MODERN_TLS).tlsVersions(TlsVersion.TLS_1_3).build()))
                .connectTimeout(5, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS).build()
            status("Connecting…", false)
            main.postDelayed(timeout, 10000)
            socket = http!!.newWebSocket(Request.Builder().url(address).build(), object : WebSocketListener() {
                private fun deliver(action: () -> Unit) { main.post { if (current == generation) action() } }
                override fun onOpen(webSocket: WebSocket, response: Response) { webSocket.send(Protocol.hello(token.trim())) }
                override fun onMessage(webSocket: WebSocket, text: String) { deliver {
                    try {
                        val m = Protocol.parse(text)
                        when (m["type"]?.jsonPrimitive?.content) {
                            "ready" -> {
                                check(!handshaken) { "Duplicate handshake" }
                                main.removeCallbacks(timeout)
                                handshaken = true
                                ready = m["capabilities"]?.jsonArray?.any { it.jsonPrimitive.content == Protocol.POINTER } == true
                                keyReady = m["capabilities"]?.jsonArray?.any { it.jsonPrimitive.content == Protocol.KEY } == true
                                onKeys(keyReady)
                                paired(address, pin.trim())
                                status(if (ready) "Connected — touchpad ready" else "Connected — pointer unavailable on desktop", ready)
                                main.postDelayed(heartbeat, 30000)
                            }
                            "ack" -> {
                                check(handshaken && pending) { "Unexpected acknowledgement" }
                                pending = false
                                main.removeCallbacks(timeout)
                            }
                            "error" -> { val message = m["error"]?.jsonPrimitive?.content ?: "Peer rejected request"; close(); status(message, false) }
                            else -> { close(); status("Unexpected peer message", false) }
                        }
                    } catch (e: Exception) { close(); status(e.message ?: "Invalid peer message", false) }
                } }
                override fun onMessage(webSocket: WebSocket, bytes: ByteString) { deliver { close(); status("Text protocol required", false) } }
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { deliver { close(); status(t.message ?: "Connection failed", false) } }
                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) { webSocket.close(code, reason); deliver { close(); status("Disconnected", false) } }
                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { deliver { close(); status("Disconnected", false) } }
            })
        } catch (e: Exception) { close(); status(e.message ?: "Connection failed", false) }
    }
    fun pointer(dx: Int = 0, dy: Int = 0, button: String = "") {
        if (!ready || pending) return
        val now = android.os.SystemClock.elapsedRealtime()
        if (button.isEmpty() && now - lastSend < 40) return
        pending = socket?.send(Protocol.pointer(dx.coerceIn(-500, 500), dy.coerceIn(-500, 500), button)) == true
        lastSend = now
        if (pending) main.postDelayed(timeout, 5000)
    }
    fun key(name: String) {
        if (!keyReady || pending) return
        pending = socket?.send(Protocol.key(name)) == true
        if (pending) main.postDelayed(timeout, 5000)
    }
    fun disconnect() { close(); status("Disconnected", false) }
    fun close() {
        generation++
        main.removeCallbacks(heartbeat)
        main.removeCallbacks(timeout)
        ready = false; keyReady = false; onKeys(false); pending = false; handshaken = false
        socket?.cancel(); socket = null
        http?.dispatcher?.executorService?.shutdown()
        http?.connectionPool?.evictAll(); http = null
    }
}
