package org.linkpad.app
import org.junit.Assert.*
import org.junit.Test
import kotlinx.serialization.json.*
class ProtocolTest {
    @Test fun pairAndReconnect() {
        val pair = Protocol.parse(Protocol.hello("secret"))
        assertEquals("pair", pair["type"]!!.jsonPrimitive.content)
        assertEquals("secret", pair["token"]!!.jsonPrimitive.content)
        assertEquals("hello", Protocol.parse(Protocol.hello(""))["type"]!!.jsonPrimitive.content)
    }
    @Test fun pointerBounds() {
        assertEquals(500, Protocol.parse(Protocol.pointer(500, -500))["dx"]!!.jsonPrimitive.int)
        assertThrows(IllegalArgumentException::class.java) { Protocol.pointer(501) }
        assertThrows(IllegalArgumentException::class.java) { Protocol.pointer(button = "middle") }
    }
    @Test fun arrowKeys() {
        assertEquals("left", Protocol.parse(Protocol.key("left"))["key"]!!.jsonPrimitive.content)
        assertThrows(IllegalArgumentException::class.java) { Protocol.key("enter") }
    }
    @Test fun rejectIncompatibleProtocol() {
        assertThrows(IllegalArgumentException::class.java) { Protocol.parse("{\"version\":2,\"type\":\"ready\"}") }
        assertThrows(IllegalArgumentException::class.java) { Protocol.parse("x".repeat(4097)) }
    }
}
