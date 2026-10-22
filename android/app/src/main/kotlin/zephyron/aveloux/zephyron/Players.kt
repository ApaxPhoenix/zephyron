package com.aveloux.zephyron

import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Plays voice messages, podcast episodes and videos with the phone's own
 * MediaPlayer. A video draws into a Flutter texture.
 */
class Players(private val textures: TextureRegistry, private val channel: MethodChannel) {
    private class Entry(val player: MediaPlayer, val producer: TextureRegistry.SurfaceProducer?)

    private val players = HashMap<Int, Entry>()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id")
        if (id == null) {
            result.error("id", "Every call names its player", null)
            return
        }
        when (call.method) {
            "open" -> open(id, call.argument<String>("path"), call.argument<Boolean>("video") == true, result)
            "play" -> {
                players[id]?.player?.start()
                result.success(null)
            }
            "pause" -> {
                players[id]?.player?.takeIf { it.isPlaying }?.pause()
                result.success(null)
            }
            "seek" -> {
                val at = call.argument<Int>("at") ?: 0
                val player = players[id]?.player
                if (Build.VERSION.SDK_INT >= 26) {
                    player?.seekTo(at.toLong(), MediaPlayer.SEEK_CLOSEST)
                } else {
                    player?.seekTo(at)
                }
                result.success(null)
            }
            "position" -> result.success(players[id]?.player?.currentPosition ?: 0)
            "close" -> {
                close(id)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun open(id: Int, path: String?, video: Boolean, result: MethodChannel.Result) {
        if (path == null) {
            result.error("path", "Nothing to play", null)
            return
        }
        close(id)
        val player = MediaPlayer()
        val producer = if (video) textures.createSurfaceProducer() else null
        var answered = false
        try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(if (video) AudioAttributes.CONTENT_TYPE_MOVIE else AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            producer?.setCallback(
                object : TextureRegistry.SurfaceProducer.Callback {
                    override fun onSurfaceAvailable() {
                        player.setSurface(producer.surface)
                    }

                    override fun onSurfaceCleanup() {
                        player.setSurface(null)
                    }
                },
            )
            player.setDataSource(path)
            player.setOnCompletionListener { channel.invokeMethod("done", mapOf("id" to id)) }
            player.setOnErrorListener { _, what, _ ->
                if (!answered) {
                    answered = true
                    result.error("play", "This could not be played ($what)", null)
                }
                true
            }
            // Phones record many videos sideways with a note to turn them;
            // a texture that does not turn them itself leaves that to Flutter.
            val turn = if (producer != null && !producer.handlesCropAndRotation()) rotation(path) else 0
            player.setOnPreparedListener {
                if (producer != null && it.videoWidth > 0 && it.videoHeight > 0) {
                    producer.setSize(it.videoWidth, it.videoHeight)
                    it.setSurface(producer.surface)
                }
                if (!answered) {
                    answered = true
                    result.success(
                        mapOf(
                            "duration" to it.duration.coerceAtLeast(0),
                            "width" to it.videoWidth,
                            "height" to it.videoHeight,
                            "rotation" to turn,
                            "texture" to producer?.id(),
                        ),
                    )
                }
            }
            players[id] = Entry(player, producer)
            player.prepareAsync()
        } catch (error: Exception) {
            players.remove(id)
            player.release()
            producer?.release()
            if (!answered) result.error("play", error.message, null)
        }
    }

    private fun rotation(path: String): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        } catch (error: Exception) {
            0
        } finally {
            retriever.release()
        }
    }

    private fun close(id: Int) {
        val entry = players.remove(id) ?: return
        try {
            entry.player.stop()
        } catch (_: IllegalStateException) {
        }
        entry.player.release()
        entry.producer?.release()
    }

    fun dispose() {
        for (id in players.keys.toList()) close(id)
    }
}
