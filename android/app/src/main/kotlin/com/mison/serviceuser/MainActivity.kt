package com.mison.serviceuser

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Enregistre un fichier (facture PDF) dans le dossier Téléchargements.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mison/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name") ?: "document.pdf"
                val bytes = call.argument<ByteArray>("bytes")
                val mime = call.argument<String>("mime") ?: "application/pdf"
                if (bytes == null) {
                    result.error("NO_DATA", "Fichier vide", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(saveToDownloads(name, bytes, mime))
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
            }
    }

    /** Android 10+ : MediaStore, sans autorisation. Avant : dossier de l'app. */
    private fun saveToDownloads(name: String, bytes: ByteArray, mime: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Téléchargements indisponible")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Écriture impossible")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return "${Environment.DIRECTORY_DOWNLOADS}/$name"
        }
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
        val file = File(dir, name)
        file.writeBytes(bytes)
        return file.absolutePath
    }
}
