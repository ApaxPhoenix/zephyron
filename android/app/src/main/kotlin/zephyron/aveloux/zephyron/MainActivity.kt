package com.aveloux.zephyron

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val channel = "zephyron/security"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Secure from the first frame: no screenshots, no screen recording and
        // a blank card in Recents until an identity chooses otherwise.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(engine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "authorized" -> result.success(signature() != null)
                "signature" -> result.success(signature())
                "packages" -> result.success(applicationInfo.nativeLibraryDir)
                "shield" -> {
                    if (call.arguments as? Boolean ?: true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
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