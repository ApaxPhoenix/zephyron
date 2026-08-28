package com.aveloux.zephyron

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val channel = "zephyron/security"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(engine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "verifyAppSignature" -> result.success(signature() != null)
                "getSignature", "signature" -> result.success(signature())
                else -> result.notImplemented()
            }
        }
    }

    private fun signature(): String? {
        return try {
            val manager = packageManager
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                manager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                manager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            }

            val array = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signer = info.signingInfo
                if (signer?.hasMultipleSigners() == true) {
                    signer.apkContentsSigners
                } else {
                    signer?.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                info.signatures
            }

            val bytes = array?.firstOrNull()?.toByteArray() ?: return null
            val hasher = MessageDigest.getInstance("SHA-256")
            val hash = hasher.digest(bytes)
            android.util.Base64.encodeToString(hash, android.util.Base64.NO_WRAP)
        } catch (error: Exception) {
            null
        }
    }
}