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

class Main : FlutterActivity() {
    private var speaker: AudioTrack? = null
    private val writer = Executors.newSingleThreadExecutor()
    private val explorer by lazy { Explorer(this) }
    private var playback: Playback? = null

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
        if (!explorer.finished(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        playback?.dispose()
        playback = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val messenger = engine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "alerts").setMethodCallHandler { call, result ->
            when (call.method) {
                "permit" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 4201)
                    }
                    result.success(null)
                }
                "show" -> {
                    Alerts.show(
                        this,
                        call.argument<Int>("id") ?: 0,
                        call.argument<String>("title") ?: "Zephyron",
                        call.argument<String>("text") ?: "",
                    )
                    result.success(null)
                }
                "cancel" -> {
                    Alerts.cancel(this, call.argument<Int>("id") ?: 0)
                    result.success(null)
                }
                "stand" -> {
                    val standby = Intent(this, Standby::class.java)
                    try {
                        if (call.argument<Boolean>("on") == true) {
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(standby) else startService(standby)
                        } else {
                            stopService(standby)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("stand", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "explorer").setMethodCallHandler { call, result ->
            explorer.handle(call, result)
        }

        val channel = MethodChannel(messenger, "playback")
        playback?.dispose()
        val made = Playback(engine.renderer, channel)
        playback = made
        channel.setMethodCallHandler { call, result -> made.handle(call, result) }

        MethodChannel(messenger, "share").setMethodCallHandler { call, result ->
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

        MethodChannel(messenger, "security").setMethodCallHandler { call, result ->
            when (call.method) {
                // Whether this install carries a signing certificate the
                // system can name, hashed as freeRASP compares it.
                "authorized" -> {
                    val hash = try {
                        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                        }
                        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
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
                        signatures?.firstOrNull()?.toByteArray()?.let {
                            android.util.Base64.encodeToString(
                                MessageDigest.getInstance("SHA-256").digest(it),
                                android.util.Base64.NO_WRAP,
                            )
                        }
                    } catch (error: Exception) {
                        null
                    }
                    result.success(hash != null)
                }
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

        MethodChannel(messenger, "sound").setMethodCallHandler { call, result ->
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

        MethodChannel(messenger, "media").setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            when (call.method) {
                // A video's or a recording's length, and a video's upright size.
                "probe" -> {
                    if (path == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val retriever = MediaMetadataRetriever()
                        val facts = try {
                            retriever.setDataSource(path)
                            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                                ?.toIntOrNull() ?: 0
                            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                                ?.toIntOrNull() ?: 0
                            val turn = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                                ?.toIntOrNull() ?: 0
                            val sideways = turn % 180 != 0
                            mapOf(
                                "duration" to (
                                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                                        ?.toIntOrNull() ?: 0
                                    ),
                                "width" to if (sideways) height else width,
                                "height" to if (sideways) width else height,
                            )
                        } catch (error: Exception) {
                            null
                        } finally {
                            retriever.release()
                        }
                        runOnUiThread { result.success(facts) }
                    }.start()
                }
                // A small JPEG of a video's first moments, made with the
                // phone's own decoder.
                "thumbnail" -> {
                    val width = call.argument<Int>("width") ?: 480
                    if (path == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val retriever = MediaMetadataRetriever()
                        val bytes = try {
                            retriever.setDataSource(path)
                            retriever.getFrameAtTime(500_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let { frame ->
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
                                out.toByteArray()
                            }
                        } catch (error: Exception) {
                            null
                        } finally {
                            retriever.release()
                        }
                        runOnUiThread { result.success(bytes) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}
