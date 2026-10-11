package com.afzal.litereader

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    private lateinit var safPlugin: SafPlugin
    private lateinit var intentPlugin: IntentPlugin
    private lateinit var volumePlugin: VolumePlugin
    private lateinit var devicePlugin: DevicePlugin

    private val openTreeRequestCode = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        safPlugin = SafPlugin(this, messenger, openTreeRequestCode)
        intentPlugin = IntentPlugin(this, messenger, intent)
        volumePlugin = VolumePlugin(messenger)
        devicePlugin = DevicePlugin(this, messenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (::intentPlugin.isInitialized) intentPlugin.onNewIntent(intent)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (::volumePlugin.isInitialized && volumePlugin.onKeyDown(keyCode)) return true
        return super.onKeyDown(keyCode, event)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (::safPlugin.isInitialized) {
            safPlugin.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::devicePlugin.isInitialized) {
            devicePlugin.onRequestPermissionsResult(requestCode, grantResults)
        }
    }
}

/**
 * Storage Access Framework bridge. Lite Reader never assumes a real file
 * path: content:// URIs are read through streams or cached copies.
 * No MANAGE_EXTERNAL_STORAGE, no storage permission at install.
 */
class SafPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val treeRequestCode: Int
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "litereader/saf")
    private var pendingTreeResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDocumentTree" -> {
                pendingTreeResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                    )
                }
                activity.startActivityForResult(intent, treeRequestCode)
            }
            "listTree" -> {
                val treeUri = Uri.parse(call.argument<String>("treeUri")!!)
                thread {
                    try {
                        val entries = listTree(treeUri)
                        activity.runOnUiThread { result.success(entries) }
                    } catch (e: Exception) {
                        activity.runOnUiThread {
                            result.error("LIST_FAILED", e.message, null)
                        }
                    }
                }
            }
            "copyToCache" -> {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val fileName = call.argument<String>("fileName")!!
                thread {
                    try {
                        val path = copyToCache(uri, fileName)
                        activity.runOnUiThread { result.success(path) }
                    } catch (e: Exception) {
                        activity.runOnUiThread {
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }
                }
            }
            "createInTree" -> {
                val treeUri = Uri.parse(call.argument<String>("treeUri")!!)
                val displayName = call.argument<String>("displayName")!!
                val mimeType = call.argument<String>("mimeType")!!
                val sourcePath = call.argument<String>("sourcePath")!!
                thread {
                    try {
                        val newUri = createInTree(treeUri, displayName, mimeType, sourcePath)
                        activity.runOnUiThread { result.success(newUri) }
                    } catch (e: Exception) {
                        activity.runOnUiThread {
                            result.error("CREATE_FAILED", e.message, null)
                        }
                    }
                }
            }
            "openWith" -> {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val mimeType = call.argument<String>("mimeType")!!
                try {
                    val view = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mimeType)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    activity.startActivity(Intent.createChooser(view, "Open with"))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != treeRequestCode) return
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        onTreePicked(uri)
    }

    fun onTreePicked(uri: Uri?) {
        val result = pendingTreeResult ?: return
        pendingTreeResult = null
        if (uri == null) {
            result.success(null)
            return
        }
        try {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            activity.contentResolver.takePersistableUriPermission(uri, flags)
        } catch (e: SecurityException) {
            // Read-only grant is still usable for listing/reading.
        }
        result.success(uri.toString())
    }

    private fun listTree(treeUri: Uri): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        walkChildren(activity.contentResolver, treeUri, treeUri, out)
        return out
    }

    private fun walkChildren(
        resolver: ContentResolver,
        treeUri: Uri,
        parentTreeUri: Uri,
        out: MutableList<Map<String, Any?>>
    ) {
        val treeDocId = DocumentsContract.getTreeDocumentId(parentTreeUri)
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, treeDocId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )
        resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idCol =
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameCol =
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeCol =
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modCol =
                cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                val docId = cursor.getString(idCol)
                val mime = cursor.getString(mimeCol) ?: "application/octet-stream"
                val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
                val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                out.add(
                    mapOf(
                        "uri" to docUri.toString(),
                        "displayName" to cursor.getString(nameCol),
                        "mimeType" to mime,
                        "size" to if (sizeCol >= 0) cursor.getLong(sizeCol) else 0L,
                        "lastModified" to if (modCol >= 0) cursor.getLong(modCol) else 0L,
                        "isDirectory" to isDir
                    )
                )
                if (isDir) {
                    val childTreeUri = DocumentsContract.buildTreeDocumentUri(
                        treeUri.authority, docId
                    ) ?: continue
                    walkChildren(resolver, treeUri, childTreeUri, out)
                }
            }
        }
    }

    private fun copyToCache(uri: Uri, fileName: String): String {
        val dir = File(activity.cacheDir, "incoming")
        if (!dir.exists()) dir.mkdirs()
        val dest = File(dir, fileName)
        activity.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(dest).use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("Cannot open ${uri}")
        return dest.absolutePath
    }

    private fun createInTree(
        treeUri: Uri,
        displayName: String,
        mimeType: String,
        sourcePath: String
    ): String {
        val resolver = activity.contentResolver
        val treeDocId = DocumentsContract.getTreeDocumentId(treeUri)
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocId)
        val newUri = DocumentsContract.createDocument(
            resolver, parentUri, mimeType, displayName
        ) ?: throw IllegalStateException("createDocument returned null")
        resolver.openOutputStream(newUri)?.use { output ->
            File(sourcePath).inputStream().use { input -> input.copyTo(output) }
        } ?: throw IllegalStateException("Cannot write to $newUri")
        return newUri.toString()
    }
}

/**
 * Handles ACTION_VIEW (content:// and file://) and ACTION_SEND for PDFs,
 * on both cold start ([getInitialFile]) and warm start ([onSharedFile]).
 */
class IntentPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
    launchIntent: Intent?
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "litereader/intent")
    private val initialFile: Map<String, Any?>? = fileFromIntent(launchIntent)
    private var consumed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInitialFile" -> {
                if (consumed) {
                    result.success(null)
                } else {
                    consumed = true
                    result.success(initialFile)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onNewIntent(intent: Intent) {
        val file = fileFromIntent(intent) ?: return
        channel.invokeMethod("onSharedFile", file)
    }

    @Suppress("DEPRECATION")
    private fun fileFromIntent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val action = intent.action
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return null
        val uri: Uri = if (action == Intent.ACTION_SEND) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as Uri?
        } else {
            intent.data
        } ?: return null
        val type = intent.type
            ?: activity.contentResolver.getType(uri)
            ?: "application/pdf"
        if (!type.startsWith("application/pdf")) return null
        return mapOf(
            "uri" to uri.toString(),
            "mimeType" to type,
            "displayName" to displayName(uri)
        )
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme != "content") return uri.lastPathSegment
        return try {
            activity.contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            uri.lastPathSegment
        }
    }
}

/** Volume keys turn pages while the reader marks them active. */
class VolumePlugin(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "litereader/volume")
    private var active = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "setActive") {
            active = call.argument<Boolean>("active") == true
            result.success(null)
        } else {
            result.notImplemented()
        }
    }

    fun onKeyDown(keyCode: Int): Boolean {
        if (!active) return false
        val direction = when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> "up"
            KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
            else -> return false
        }
        channel.invokeMethod("onVolumeKey", direction)
        return true
    }
}

/** Keep-screen-awake flag and camera permission (requested only for Scan). */
class DevicePlugin(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "litereader/device")
    private var pendingPermissionResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setKeepAwake" -> {
                val keep = call.argument<Boolean>("keepAwake") == true
                activity.runOnUiThread {
                    if (keep) {
                        activity.window.addFlags(
                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        )
                    } else {
                        activity.window.clearFlags(
                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        )
                    }
                }
                result.success(null)
            }
            "isCameraGranted" -> {
                result.success(
                    ContextCompat.checkSelfPermission(
                        activity, android.Manifest.permission.CAMERA
                    ) == PackageManager.PERMISSION_GRANTED
                )
            }
            "requestCamera" -> {
                pendingPermissionResult = result
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(android.Manifest.permission.CAMERA),
                    REQUEST_CAMERA
                )
            }
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CAMERA) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    companion object {
        private const val REQUEST_CAMERA = 2001
    }
}
