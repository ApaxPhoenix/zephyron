package com.aveloux.zephyron

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException

/**
 * Hands single files to other apps, so a share sheet can read an exported
 * attachment and the camera can write a photo, without a library.
 *
 * Only files in the cache's outbox are served, the same folder the app
 * wipes whenever the vault locks, and only to apps it grants a URI to.
 */
class Vault : ContentProvider() {
    companion object {
        fun authority(context: Context) = "${context.packageName}.vault"

        fun outbox(context: Context): File =
            File(context.cacheDir, "outbox").also { it.mkdirs() }

        /** A URI other apps can be granted for [file], which must be in the outbox. */
        fun uri(context: Context, file: File): Uri {
            val root = outbox(context).canonicalFile
            val target = file.canonicalFile
            require(target.path.startsWith(root.path + File.separator)) { "Not in the outbox" }
            val relative = target.path.substring(root.path.length + 1).replace(File.separatorChar, '/')
            return Uri.Builder()
                .scheme("content")
                .authority(authority(context))
                .encodedPath("/" + relative.split('/').joinToString("/") { Uri.encode(it) })
                .build()
        }

        fun mime(name: String): String =
            MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
                ?: "application/octet-stream"
    }

    override fun onCreate() = true

    private fun file(uri: Uri): File? {
        val context = context ?: return null
        val root = outbox(context).canonicalFile
        val path = uri.path ?: return null
        val target = File(root, path).canonicalFile
        return if (target.path.startsWith(root.path + File.separator)) target else null
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val target = file(uri) ?: throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(target, ParcelFileDescriptor.parseMode(mode))
    }

    override fun getType(uri: Uri): String? = file(uri)?.let { mime(it.name) }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        val target = file(uri) ?: return null
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns)
        cursor.addRow(
            columns.map {
                when (it) {
                    OpenableColumns.DISPLAY_NAME -> target.name
                    OpenableColumns.SIZE -> target.length()
                    else -> null
                }
            },
        )
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ) = 0
}
