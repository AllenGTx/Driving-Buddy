package com.drivingbuddy

import android.app.Activity
import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val PICKER_CHANNEL = "com.drivingbuddy/audio_picker"
    private val DEVICE_CHANNEL = "com.drivingbuddy/device_control"
    private val PICK_AUDIO_REQUEST = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var duckFocusRequest: AudioFocusRequest? = null
    private var exclusiveFocusRequest: AudioFocusRequest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PICKER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickAudio") {
                if (pendingResult != null) {
                    result.error("ALREADY_ACTIVE", "Audio picker is already running", null)
                    return@setMethodCallHandler
                }
                pendingResult = result

                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "audio/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav", "audio/ogg", "audio/m4a", "audio/aac"))
                }
                startActivityForResult(Intent.createChooser(intent, "Pilih File Audio"), PICK_AUDIO_REQUEST)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL).setMethodCallHandler { call, result ->
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "isInPhoneOrVoipCall" -> {
                    val mode = audioManager.mode
                    val inCall = mode == AudioManager.MODE_IN_CALL ||
                        mode == AudioManager.MODE_IN_COMMUNICATION ||
                        mode == AudioManager.MODE_RINGTONE
                    result.success(inCall)
                }
                "setAudioDucking" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    val exclusive = call.argument<Boolean>("exclusive") ?: false
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            if (enable) {
                                val attrs = AudioAttributes.Builder()
                                    .setUsage(if (exclusive) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                    .build()
                                if (exclusive) {
                                    val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                                        .setAudioAttributes(attrs)
                                        .build()
                                    exclusiveFocusRequest = req
                                    audioManager.requestAudioFocus(req)
                                } else {
                                    val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                                        .setAudioAttributes(attrs)
                                        .setWillPauseWhenDucked(false)
                                        .build()
                                    duckFocusRequest = req
                                    audioManager.requestAudioFocus(req)
                                }
                            } else {
                                duckFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
                                exclusiveFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
                                duckFocusRequest = null
                                exclusiveFocusRequest = null
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "isSpotifyInstalled" -> {
                    val installed = isPkgInstalled("com.spotify.music") || isPkgInstalled("com.spotify.lite")
                    result.success(installed)
                }
                "isMusicActive" -> {
                    result.success(audioManager.isMusicActive)
                }
                "sendMediaCommand" -> {
                    val cmd = call.argument<String>("command") ?: "play_pause"
                    val keyCode = when (cmd) {
                        "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                        "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                        "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                        "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                        else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                    }
                    try {
                        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "playSpotifyQuery" -> {
                    val query = call.argument<String>("query") ?: ""
                    val pkg = when {
                        isPkgInstalled("com.spotify.music") -> "com.spotify.music"
                        isPkgInstalled("com.spotify.lite") -> "com.spotify.lite"
                        else -> null
                    }
                    if (pkg == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val playIntent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                            setPackage(pkg)
                            putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                            putExtra(SearchManager.QUERY, query)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(playIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val searchUri = Uri.parse("spotify:search:${Uri.encode(query)}")
                            val fallback = Intent(Intent.ACTION_VIEW, searchUri).apply {
                                setPackage(pkg)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(fallback)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isPkgInstalled(pkg: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(pkg, 0)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_AUDIO_REQUEST) {
            val result = pendingResult ?: return
            pendingResult = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                try {
                    var displayName = "alarm_custom.mp3"
                    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIndex != -1) {
                                displayName = cursor.getString(nameIndex) ?: displayName
                            }
                        }
                    }

                    val cachedFile = File(cacheDir, displayName)
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(cachedFile).use { output ->
                            input.copyTo(output)
                        }
                    }

                    val map = HashMap<String, String>()
                    map["path"] = cachedFile.absolutePath
                    map["name"] = displayName
                    result.success(map)
                } catch (e: Exception) {
                    result.error("ERROR", "Gagal memproses file audio: ${e.message}", null)
                }
            } else {
                result.success(null)
            }
        }
    }
}
