package com.drivingbuddy

import android.app.Activity
import android.app.SearchManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.browse.MediaBrowser
import android.media.session.MediaController
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
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
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            // Cold launch baru -> pastikan status Dynamic Island sesi lama tidak terbawa
            SpotifySessionPrefs.setDynamicIslandActive(applicationContext, false)
            try {
                stopService(Intent(this, AppTaskWatcherService::class.java))
            } catch (_: Exception) {
            }
        }
    }

    override fun onDestroy() {
        if (isFinishing && SpotifySessionPrefs.isDynamicIslandActive(applicationContext)) {
            SpotifyMediaHelper.pauseSpotify(applicationContext)
            SpotifySessionPrefs.setDynamicIslandActive(applicationContext, false)
            try {
                stopService(Intent(this, AppTaskWatcherService::class.java))
            } catch (_: Exception) {
            }
        }
        super.onDestroy()
    }

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
                "isNotificationAccessGranted" -> {
                    result.success(SpotifyMediaHelper.isNotificationAccessGranted(this))
                }
                "openNotificationAccessSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "openSpotifyApp" -> {
                    val pkg = when {
                        isPkgInstalled("com.spotify.music") -> "com.spotify.music"
                        isPkgInstalled("com.spotify.lite") -> "com.spotify.lite"
                        else -> null
                    }
                    if (pkg == null) {
                        result.success(false)
                    } else {
                        try {
                            val launch = packageManager.getLaunchIntentForPackage(pkg)?.apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            if (launch != null) {
                                startActivity(launch)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                "getSpotifyPlaybackState" -> {
                    val lastArtHash = call.argument<String>("lastArtHash") ?: ""
                    result.success(SpotifyMediaHelper.getPlaybackSnapshot(this, lastArtHash))
                }
                "seekSpotify" -> {
                    val posMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                    result.success(SpotifyMediaHelper.seekSpotify(this, posMs))
                }
                "setDynamicIslandSessionActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    SpotifySessionPrefs.setDynamicIslandActive(applicationContext, active)
                    val svcIntent = Intent(this, AppTaskWatcherService::class.java)
                    try {
                        if (active) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(svcIntent)
                            } else {
                                startService(svcIntent)
                            }
                        } else {
                            stopService(svcIntent)
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "isDynamicIslandSessionActive" -> {
                    result.success(SpotifySessionPrefs.isDynamicIslandActive(applicationContext))
                }
                "isMusicActive" -> {
                    SpotifyMediaHelper.refreshStateFromMediaSession(this)
                    val hasActiveSession = SpotifyMediaHelper.findActiveSpotifyController(this) != null
                    result.success(
                        if (hasActiveSession) SpotifyStateHolder.isPlaying else audioManager.isMusicActive
                    )
                }
                "sendMediaCommand" -> {
                    val cmd = call.argument<String>("command") ?: "play_pause"
                    result.success(SpotifyMediaHelper.sendSpotifyCommand(this, cmd))
                }
                "playSpotifyQuery" -> {
                    val query = call.argument<String>("query") ?: ""
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val pkg = when {
                        isPkgInstalled("com.spotify.music") -> "com.spotify.music"
                        isPkgInstalled("com.spotify.lite") -> "com.spotify.lite"
                        else -> null
                    }
                    if (pkg == null) {
                        result.success("not_installed")
                        return@setMethodCallHandler
                    }
                    if (!SpotifyMediaHelper.isNotificationAccessGranted(this)) {
                        result.success("needs_notification_access")
                        return@setMethodCallHandler
                    }

                    val extras = Bundle().apply {
                        putString(MediaStore.EXTRA_MEDIA_FOCUS, MediaStore.Audio.Media.ENTRY_CONTENT_TYPE)
                        putString(SearchManager.QUERY, query)
                        if (title.isNotEmpty()) putString(MediaStore.EXTRA_MEDIA_TITLE, title)
                        if (artist.isNotEmpty()) putString(MediaStore.EXTRA_MEDIA_ARTIST, artist)
                    }

                    // Jalur UTAMA: kontrol langsung MediaSession Spotify di latar belakang (0 pindah layar)
                    val existingCtrl = SpotifyMediaHelper.findActiveSpotifyController(this)
                    if (existingCtrl != null) {
                        try {
                            existingCtrl.transportControls.playFromSearch(query, extras)
                            result.success("ok")
                            return@setMethodCallHandler
                        } catch (_: Exception) {
                        }
                    }

                    // Jika Spotify belum punya sesi aktif, bangunkan MediaBrowserService di background tanpa startActivity
                    playSpotifyViaBackgroundService(pkg, query, extras, audioManager, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Putar lagu di Spotify 100% di latar belakang (tanpa pernah memanggil startActivity / pindah aplikasi)
     * melalui MediaBrowserService + polling MediaSession, lalu `prepareFromSearch` + `playFromSearch`.
     */
    private fun playSpotifyViaBackgroundService(
        pkg: String,
        query: String,
        extras: Bundle,
        audioManager: AudioManager,
        result: MethodChannel.Result,
    ) {
        var replied = false
        var browser: MediaBrowser? = null

        fun finishWith(status: String) {
            if (replied) return
            replied = true
            try {
                browser?.disconnect()
            } catch (_: Exception) {
            }
            browser = null
            result.success(status)
        }

        // 1. Bind MediaBrowserService milik Spotify secara senyap di latar belakang
        try {
            val svcIntent = Intent("android.media.browse.MediaBrowserService").apply {
                setPackage(pkg)
            }
            @Suppress("DEPRECATION")
            val matches = packageManager.queryIntentServices(svcIntent, 0)
            val svcInfo = matches.firstOrNull()?.serviceInfo
            if (svcInfo != null) {
                val comp = ComponentName(svcInfo.packageName, svcInfo.name)
                lateinit var mb: MediaBrowser
                val cb = object : MediaBrowser.ConnectionCallback() {
                    override fun onConnected() {
                        if (replied) return
                        try {
                            val token = mb.sessionToken
                            val ctrl = MediaController(this@MainActivity, token)
                            ctrl.transportControls.playFromSearch(query, extras)
                            finishWith("ok")
                        } catch (_: Exception) {
                        }
                    }
                }
                mb = MediaBrowser(this, comp, cb, null)
                browser = mb
                mb.connect()
            }
        } catch (_: Exception) {
        }

        // 2. Polling hingga 5x (tiap 220ms) menunggu MediaSession aktif sesudah service dibangunkan
        fun pollController(attempt: Int) {
            if (replied) return
            val ctrl = SpotifyMediaHelper.findActiveSpotifyController(this@MainActivity)
            if (ctrl != null) {
                try {
                    ctrl.transportControls.playFromSearch(query, extras)
                    finishWith("ok")
                    return
                } catch (_: Exception) {
                }
            }
            if (attempt < 5) {
                mainHandler.postDelayed({ pollController(attempt + 1) }, 220L)
                return
            }

            // 3. Fallback senyap terakhir: bangunkan via KEYCODE_MEDIA_PLAY lalu langsung timpa dengan playFromSearch;
            // bila tetap tidak muncul sesi aktif, langsung PAUSE agar lagu lama tidak lanjut berputar.
            try {
                audioManager.dispatchMediaKeyEvent(
                    android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PLAY),
                )
                audioManager.dispatchMediaKeyEvent(
                    android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_MEDIA_PLAY),
                )
                mainHandler.postDelayed({
                    if (replied) return@postDelayed
                    val wokenCtrl = SpotifyMediaHelper.findActiveSpotifyController(this@MainActivity)
                    if (wokenCtrl != null) {
                        try {
                            wokenCtrl.transportControls.playFromSearch(query, extras)
                            finishWith("ok")
                            return@postDelayed
                        } catch (_: Exception) {
                        }
                    }
                    try {
                        audioManager.dispatchMediaKeyEvent(
                            android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PAUSE),
                        )
                        audioManager.dispatchMediaKeyEvent(
                            android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_MEDIA_PAUSE),
                        )
                    } catch (_: Exception) {
                    }
                    finishWith("spotify_not_active")
                }, 650L)
            } catch (_: Exception) {
                finishWith("failed")
            }
        }

        mainHandler.postDelayed({ pollController(0) }, 240L)
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
