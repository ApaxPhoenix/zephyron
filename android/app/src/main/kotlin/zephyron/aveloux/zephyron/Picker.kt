package com.aveloux.zephyron

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * Picks photos, videos and files with the system's own pickers, and takes
 * photos with the camera app, without storage permissions.
 *
 * Whatever is picked is copied into the outbox, so the app reads a plain
 * file that is wiped when the vault locks. Photos are scaled down and
 * turned upright on the way, except GIFs, which keep their animation.
 */
class Picker(private val activity: Activity) {
    private companion object {
        const val GALLERY = 4101
        const val CAMERA = 4102
        const val VIDEO = 4103
        const val FILE = 4104
    }

    private var pending: MethodChannel.Result? = null
    private var limit = 2560
    private var quality = 88
    private var shot: File? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A picker is already open", null)
            return
        }
        limit = call.argument<Int>("limit") ?: 2560
        quality = call.argument<Int>("quality") ?: 88
        val (intent, code) = when (call.method) {
            "photo" -> gallery("image/*") to GALLERY
            "video" -> gallery("video/*") to VIDEO
            "camera" -> camera(call.argument<Boolean>("front") == true) to CAMERA
            "file" -> Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = call.argument<String>("type") ?: "*/*"
            } to FILE
            else -> {
                result.notImplemented()
                return
            }
        }
        pending = result
        try {
            activity.startActivityForResult(intent, code)
        } catch (error: ActivityNotFoundException) {
            pending = null
            result.error("missing", "Nothing on this phone can do that", null)
        }
    }

    private fun gallery(type: String): Intent =
        if (Build.VERSION.SDK_INT >= 33) {
            Intent(MediaStore.ACTION_PICK_IMAGES).setType(type)
        } else {
            Intent(Intent.ACTION_GET_CONTENT).addCategory(Intent.CATEGORY_OPENABLE).setType(type)
        }

    private fun camera(front: Boolean): Intent {
        val file = File(Vault.outbox(activity), "camera-${UUID.randomUUID()}.jpg")
        shot = file
        val uri = Vault.uri(activity, file)
        return Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            clipData = ClipData.newRawUri("", uri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (front) {
                // Not part of the platform, but most camera apps honour one of these.
                putExtra("android.intent.extras.CAMERA_FACING", 1)
                putExtra("android.intent.extras.LENS_FACING_FRONT", 1)
                putExtra("android.intent.extra.USE_FRONT_CAMERA", true)
            }
        }
    }

    /** Returns whether the result was one of the picker's. */
    fun finished(code: Int, status: Int, data: Intent?): Boolean {
        if (code !in GALLERY..FILE) return false
        val result = pending ?: return true
        pending = null
        val uri = if (code == CAMERA) shot?.let { Vault.uri(activity, it) } else data?.data
        if (status != Activity.RESULT_OK || uri == null) {
            shot?.delete()
            shot = null
            result.success(null)
            return true
        }
        val photo = code == GALLERY || code == CAMERA
        val taken = shot
        Thread {
            val picked = try {
                copy(uri, photo)
            } catch (error: Exception) {
                null
            } finally {
                if (code == CAMERA) taken?.delete()
            }
            activity.runOnUiThread { result.success(picked) }
        }.start()
        shot = null
        return true
    }

    private fun named(uri: Uri): String {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) {
                val name = it.getString(0)
                if (!name.isNullOrBlank()) return name
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "file"
    }

    private fun copy(uri: Uri, photo: Boolean): Map<String, Any> {
        val resolver = activity.contentResolver
        val name = named(uri).replace(Regex("[^\\w.\\- ]"), "_")
        val mime = resolver.getType(uri) ?: Vault.mime(name)
        val folder = Vault.outbox(activity)
        if (photo && mime != "image/gif") {
            shrink(uri)?.let { bitmap ->
                val base = name.substringBeforeLast('.', name)
                val file = File(folder, "picked-${UUID.randomUUID()}-$base.jpg")
                FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }
                bitmap.recycle()
                return mapOf("path" to file.path, "name" to "$base.jpg", "mime" to "image/jpeg", "size" to file.length())
            }
        }
        val file = File(folder, "picked-${UUID.randomUUID()}-$name")
        resolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Could not open what was picked" }
            FileOutputStream(file).use { input.copyTo(it) }
        }
        return mapOf("path" to file.path, "name" to name, "mime" to mime, "size" to file.length())
    }

    /** Decodes a photo no larger than [limit] on its long side, turned upright. */
    private fun shrink(uri: Uri): Bitmap? {
        val resolver = activity.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        if (longest <= 0) return null
        var sample = 1
        while (longest / (sample * 2) >= limit) sample *= 2
        val decoded = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val turn = resolver.openInputStream(uri)?.use {
            when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } ?: 0f
        val scale = minOf(1f, limit.toFloat() / maxOf(decoded.width, decoded.height))
        if (turn == 0f && scale >= 1f) return decoded
        val matrix = Matrix().apply {
            postScale(scale, scale)
            postRotate(turn)
        }
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        if (upright !== decoded) decoded.recycle()
        return upright
    }
}
