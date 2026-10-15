package org.linkpad.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    private var activeClient: PeerClient? = null
    override fun onStop() { activeClient?.disconnect(); super.onStop() }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("peer", MODE_PRIVATE)
        setContent { MaterialTheme {
            var address by remember { mutableStateOf(prefs.getString("address", "wss://192.168.1.10:4747/ws")!!) }
            var pin by remember { mutableStateOf(prefs.getString("pin", "")!!) }
            var token by remember { mutableStateOf("") }
            var message by remember { mutableStateOf("Enter the desktop address and verify its fingerprint") }
            var enabled by remember { mutableStateOf(false) }
            var keyEnabled by remember { mutableStateOf(false) }
            val client = remember { PeerClient({ text, available -> message = text; enabled = available }, { connectedAddress, connectedPin ->
                prefs.edit().putString("address", connectedAddress).putString("pin", connectedPin).apply()
                token = ""
            }, { keyEnabled = it }).also { activeClient = it } }
            DisposableEffect(Unit) { onDispose { client.close(); activeClient = null } }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Linkpad", style = MaterialTheme.typography.headlineLarge)
                Text("Local device connection · early development build")
                OutlinedTextField(address, { address = it }, label = { Text("Desktop address") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(pin, { pin = it }, label = { Text("Verified SHA-256 fingerprint") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(token, { token = it }, label = { Text("Pairing secret (first connection only)") }, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { client.connect(address.trim(), pin, token) }) { Text("Connect / pair") }
                    OutlinedButton(onClick = { client.close(); enabled = false; message = "Disconnected" }) { Text("Disconnect") }
                }
                Text(message)
                Box(Modifier.fillMaxWidth().height(220.dp).background(MaterialTheme.colorScheme.surfaceVariant)
                    .pointerInput(enabled) { if (enabled) detectDragGestures { change, delta -> change.consume(); client.pointer(delta.x.roundToInt(), delta.y.roundToInt()) } }, contentAlignment = Alignment.Center) {
                    Text(if (enabled) "Drag to move pointer" else "Touchpad unavailable")
                }
                // ponytail: D-pad sends arrow keys via key.v1.
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    OutlinedButton(enabled = keyEnabled, onClick = { client.key("left") }) { Text("←") }
                    OutlinedButton(enabled = keyEnabled, onClick = { client.key("up") }) { Text("↑") }
                    OutlinedButton(enabled = keyEnabled, onClick = { client.key("down") }) { Text("↓") }
                    OutlinedButton(enabled = keyEnabled, onClick = { client.key("right") }) { Text("→") }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(enabled = enabled, onClick = { client.pointer(button = "left") }) { Text("Left click") }
                    Button(enabled = enabled, onClick = { client.pointer(button = "right") }) { Text("Right click") }
                }
                Text("Verify the fingerprint directly on your desktop before pairing. The secret expires after two minutes. The app disconnects when backgrounded.")
            }
        } }
    }
}
