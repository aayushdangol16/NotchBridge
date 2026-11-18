package com.notchbridge.android

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM, wire-compatible with CryptoKit's `AES.GCM.SealedBox.combined`:
 * nonce(12) | ciphertext | tag(16).
 */
class Crypto(key: ByteArray) {
    private val secret = SecretKeySpec(key, "AES")
    private val random = SecureRandom()

    fun seal(plain: ByteArray): ByteArray {
        val nonce = ByteArray(NONCE).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secret, GCMParameterSpec(TAG_BITS, nonce))
        return nonce + cipher.doFinal(plain)
    }

    fun open(box: ByteArray): ByteArray {
        require(box.size > NONCE + TAG_BITS / 8) { "frame too short" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(TAG_BITS, box, 0, NONCE))
        return cipher.doFinal(box, NONCE, box.size - NONCE)
    }

    private companion object {
        const val NONCE = 12
        const val TAG_BITS = 128
    }
}
