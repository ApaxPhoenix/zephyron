package com.aveloux.zephyron

import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
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

        MethodChannel(engine.dartExecutor.binaryMessenger, "zephyron/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "thumbnail" -> {
                    val path = call.argument<String>("path")
                    val width = call.argument<Int>("width") ?: 480
                    if (path == null) {
                        result.success(null)
                    } else {
                        Thread {
                            val bytes = try {
                                still(path, width)
                            } catch (error: Exception) {
                                null
                            }
                            runOnUiThread { result.success(bytes) }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** A small JPEG of a video's first moments, made with the phone's own decoder. */
    private fun still(path: String, width: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val frame = retriever.getFrameAtTime(500_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null
            val scale = width.toFloat() / maxOf(frame.width, frame.height)
            val sized = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    frame,
                    (frame.width * scale).toInt().coerceAtLeast(1),
                    (frame.height * scale).toInt().coerceAtLeast(1),
                    true,
                )
            } else {
                frame
            }
            val out = ByteArrayOutputStream()
            sized.compress(Bitmap.CompressFormat.JPEG, 70, out)
            return out.toByteArray()
        } finally {
            retriever.release()
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