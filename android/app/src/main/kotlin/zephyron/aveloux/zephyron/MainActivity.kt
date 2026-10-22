package com.aveloux.zephyron

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channel = "zephyron/security"
    private var speaker: AudioTrack? = null
    private val writer = Executors.newSingleThreadExecutor()
    private val picker by lazy { Picker(this) }
    private var players: Players? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Secure from the first frame: no screenshots, no screen recording and
        // a blank card in Recents until an identity chooses otherwise.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    @Deprecated("Flutter's activity still delivers results this way")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!picker.finished(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        players?.dispose()
        players = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(engine.dartExecutor.binaryMessenger, "zephyron/picker").setMethodCallHandler { call, result ->
            picker.handle(call, result)
        }

        val playback = MethodChannel(engine.dartExecutor.binaryMessenger, "zephyron/player")
        players?.dispose()
        val made = Players(engine.renderer, playback)
        players = made
        playback.setMethodCallHandler { call, result -> made.handle(call, result) }

        MethodChannel(engine.dartExecutor.binaryMessenger, "zephyron/share").setMethodCallHandler { call, result ->
            try {
                val intent = Intent(Intent.ACTION_SEND)
                when (call.method) {
                    "text" -> {
                        intent.type = "text/plain"
                        intent.putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                        call.argument<String>("subject")?.let { intent.putExtra(Intent.EXTRA_SUBJECT, it) }
                    }
                    "file" -> {
                        val file = File(requireNotNull(call.argument<String>("path")))
                        val uri = Vault.uri(this, file)
                        intent.type = call.argument<String>("mime") ?: Vault.mime(file.name)
                        intent.putExtra(Intent.EXTRA_STREAM, uri)
                        intent.clipData = ClipData.newRawUri("", uri)
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                startActivity(Intent.createChooser(intent, call.argument<String>("title")))
                result.success(null)
            } catch (error: Exception) {
                result.error("share", error.message, null)
            }
        }

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

        MethodChannel(engine.dartExecutor.binaryMessenger, "zephyron/sound").setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val rate = call.argument<Int>("rate") ?: 8000
                    speaker?.release()
                    val size = AudioTrack.getMinBufferSize(
                        rate,
                        AudioFormat.CHANNEL_OUT_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                    )
                    speaker = AudioTrack.Builder()
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build(),
                        )
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setSampleRate(rate)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                                .build(),
                        )
                        .setBufferSizeInBytes(maxOf(size, rate))
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .build()
                        .also { it.play() }
                    result.success(null)
                }
                "feed" -> {
                    val pcm = call.argument<ByteArray>("pcm")
                    val track = speaker
                    if (pcm != null && track != null) {
                        // Writing blocks while the buffer is full, so it never
                        // runs on the UI thread.
                        writer.execute { track.write(pcm, 0, pcm.size) }
                    }
                    result.success(null)
                }
                "close" -> {
                    val track = speaker
                    speaker = null
                    writer.execute {
                        track?.stop()
                        track?.release()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(engine.dartExecutor.binaryMessenger, "zephyron/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(null)
                    } else {
                        Thread {
                            val facts = try {
                                probe(path)
                            } catch (error: Exception) {
                                null
                            }
                            runOnUiThread { result.success(facts) }
                        }.start()
                    }
                }
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

    /** A video's or a recording's length, and a video's upright size. */
    private fun probe(path: String): Map<String, Int> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            fun read(key: Int) = retriever.extractMetadata(key)?.toIntOrNull() ?: 0
            val width = read(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val height = read(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val sideways = read(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) % 180 != 0
            return mapOf(
                "duration" to read(MediaMetadataRetriever.METADATA_KEY_DURATION),
                "width" to if (sideways) height else width,
                "height" to if (sideways) width else height,
            )
        } finally {
            retriever.release()
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