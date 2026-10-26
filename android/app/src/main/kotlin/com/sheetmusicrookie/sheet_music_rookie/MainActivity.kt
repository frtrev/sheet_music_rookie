package com.sheetmusicrookie.sheet_music_rookie

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "sheet_music_rookie/incoming_file"
    private var channel: MethodChannel? = null
    private var pendingFilePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getInitialFile") {
                    result.success(pendingFilePath)
                    pendingFilePath = null
                } else {
                    result.notImplemented()
                }
            }
        }
        captureMusicXml(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureMusicXml(intent, notifyFlutter = true)
    }

    private fun captureMusicXml(intent: Intent?, notifyFlutter: Boolean) {
        if (intent == null) return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            else -> null
        } ?: return
        val path = copyIncomingFile(uri) ?: return
        pendingFilePath = path
        if (notifyFlutter) {
            channel?.invokeMethod("fileOpened", path)
            pendingFilePath = null
        }
    }

    private fun copyIncomingFile(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        val displayName = queryDisplayName(uri) ?: "Shared Score.musicxml"
        val safeName = displayName.substringAfterLast('/').substringAfterLast('\\')
        val directory = File(File(cacheDir, "incoming-musicxml"), java.util.UUID.randomUUID().toString()).apply { mkdirs() }
        val destination = File(directory, safeName)
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            destination.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) cursor.getString(0) else null
        } catch (_: Exception) {
            null
        } finally {
            cursor?.close()
        }
    }
}
