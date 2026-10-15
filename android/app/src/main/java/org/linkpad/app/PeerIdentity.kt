package org.linkpad.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import javax.net.ssl.*
import javax.security.auth.x500.X500Principal

object PeerIdentity {
    private const val ALIAS = "linkpad-peer-v1"
    fun context(pin: String): Pair<SSLContext, X509TrustManager> {
        require(pin.matches(Regex("[0-9a-fA-F]{64}"))) { "Fingerprint must have 64 hexadecimal characters" }
        val expected = pin.lowercase()
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!store.containsAlias(ALIAS)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setCertificateSubject(X500Principal("CN=Linkpad Android peer"))
                    .setCertificateSerialNumber(BigInteger.ONE)
                    .setCertificateNotBefore(Date(System.currentTimeMillis() - 3600000))
                    .setCertificateNotAfter(Date(System.currentTimeMillis() + 315360000000L))
                    .build())
                generateKeyPair()
            }
        }
        val km = object : X509KeyManager {
            override fun getClientAliases(keyType: String?, issuers: Array<java.security.Principal>?): Array<String> = arrayOf(ALIAS)
            override fun chooseClientAlias(keyType: Array<String>?, issuers: Array<java.security.Principal>?, socket: java.net.Socket?): String? =
                if (keyType?.contains("EC") == true) ALIAS else null
            override fun getServerAliases(keyType: String?, issuers: Array<java.security.Principal>?): Array<String>? = null
            override fun chooseServerAlias(keyType: String?, issuers: Array<java.security.Principal>?, socket: java.net.Socket?): String? = null
            override fun getCertificateChain(alias: String?): Array<X509Certificate> = arrayOf(store.getCertificate(ALIAS) as X509Certificate)
            override fun getPrivateKey(alias: String?): PrivateKey = store.getKey(ALIAS, null) as PrivateKey
        }
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) { throw java.security.cert.CertificateException("Not a server") }
            override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) {
                if (chain == null || chain.size != 1) throw java.security.cert.CertificateException("Single peer identity required")
                chain[0].checkValidity()
                val actual = MessageDigest.getInstance("SHA-256").digest(chain[0].encoded).joinToString("") { "%02x".format(it.toInt() and 255) }
                if (actual != expected) throw java.security.cert.CertificateException("Desktop fingerprint mismatch")
            }
        }
        val context = SSLContext.getInstance("TLSv1.3").apply { init(arrayOf(km), arrayOf(trust), null) }
        return context to trust
    }
}
