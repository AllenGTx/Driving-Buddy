package com.drivingbuddy

import android.app.Notification
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.text.TextUtils
import android.util.Base64
import android.view.KeyEvent
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min

/**
 * Menjaga state pemutaran Spotify nyata secara real-time di RAM
 * agar Dynamic Island, timer sinkronisasi, dan pause-saat-tutup-app selalu akurat.
 */
object SpotifyStateHolder {
    private val SPOTIFY_PACKAGES = setOf("com.spotify.music", "com.spotify.lite")

    @Volatile var packageName: String = ""
    @Volatile var title: String = ""
    @Volatile var artist: String = ""
    @Volatile var album: String = ""
    @Volatile var durationMs: Long = 0L
    @Volatile var basePositionMs: Long = 0L
    @Volatile var lastUpdateElapsedMs: Long = 0L
    @Volatile var playbackSpeed: Float = 1.0f
    @Volatile var isPlaying: Boolean = false
    @Volatile var isAd: Boolean = false
    @Volatile var artUri: String = ""
    @Volatile var artHash: String = ""
    @Volatile var artBase64: String = ""
    @Volatile var hasSession: Boolean = false

    fun isSpotifyPackage(pkg: String?): Boolean {
        return pkg != null && SPOTIFY_PACKAGES.contains(pkg)
    }

    fun updateFromMetadata(pkg: String, meta: MediaMetadata?) {
        if (meta == null) return
        packageName = pkg
        hasSession = true

        val rawTitle = meta.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: ""
        val rawArtist = meta.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
            ?: ""
        val rawAlbum = meta.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
        val mediaId = meta.getString(MediaMetadata.METADATA_KEY_MEDIA_ID) ?: ""
        val dur = meta.getLong(MediaMetadata.METADATA_KEY_DURATION)

        val adDetected = detectAd(rawTitle, rawArtist, rawAlbum, mediaId, dur)
        isAd = adDetected
        title = if (adDetected && rawTitle.isBlank()) "Iklan Spotify" else rawTitle
        artist = if (adDetected && rawArtist.isBlank()) "Spotify Advertisement" else rawArtist
        album = rawAlbum
        if (dur > 0L) {
            durationMs = dur
        } else if (adDetected && durationMs <= 0L) {
            durationMs = 30000L
        }

        val uri = meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
            ?: meta.getString(MediaMetadata.METADATA_KEY_ART_URI)
            ?: ""
        if (uri.isNotEmpty()) {
            artUri = uri
        }

        val bmp = meta.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: meta.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: meta.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        if (bmp != null) {
            cacheBitmap(bmp, "${pkg}|${title}|${artist}|${bmp.width}x${bmp.height}")
        } else if (adDetected) {
            artBase64 = ""
            artHash = "ad:$title"
        }
    }

    fun updateFromPlaybackState(pkg: String, state: PlaybackState?) {
        if (state == null) return
        packageName = pkg
        hasSession = true
        val st = state.state
        isPlaying = st == PlaybackState.STATE_PLAYING || st == PlaybackState.STATE_BUFFERING
        basePositionMs = max(0L, state.position)
        lastUpdateElapsedMs = if (state.lastPositionUpdateTime > 0L) {
            state.lastPositionUpdateTime
        } else {
            SystemClock.elapsedRealtime()
        }
        playbackSpeed = if (state.playbackSpeed > 0f) state.playbackSpeed else 1.0f
    }

    fun updateFromNotification(pkg: String, notif: Notification) {
        val extras = notif.extras ?: return
        val nTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val nArtist = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        val nAlbum = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim() ?: ""
        if (nTitle.isEmpty()) return

        packageName = pkg
        hasSession = true
        val adDetected = detectAd(nTitle, nArtist, nAlbum, "", durationMs)
        isAd = adDetected
        title = nTitle
        if (nArtist.isNotEmpty()) artist = nArtist
        if (nAlbum.isNotEmpty()) album = nAlbum
    }

    fun computeCurrentPositionMs(): Long {
        if (!hasSession) return 0L
        var pos = basePositionMs
        if (isPlaying && lastUpdateElapsedMs > 0L) {
            val delta = max(0L, SystemClock.elapsedRealtime() - lastUpdateElapsedMs)
            pos += (delta * playbackSpeed).toLong()
        }
        return if (durationMs > 0L) min(pos, durationMs) else max(0L, pos)
    }

    private fun detectAd(
        t: String,
        a: String,
        al: String,
        mediaId: String,
        durMs: Long,
    ): Boolean {
        val tl = t.trim().lowercase()
        val alLow = a.trim().lowercase()
        val mid = mediaId.trim().lowercase()
        if (mid.contains(":ad:") || mid.startsWith("spotify:ad")) return true
        if (tl == "advertisement" || tl == "iklan" || tl == "spotify free" || tl == "sponsored") {
            return true
        }
        if (tl == "spotify" && (alLow.isEmpty() || alLow == "spotify")) return true
        if (durMs in 1L..45000L && (alLow.isEmpty() || alLow == "spotify") && al.isBlank()) {
            return true
        }
        return false
    }

    private fun cacheBitmap(bitmap: Bitmap, signature: String) {
        val newHash = signature.hashCode().toString()
        if (newHash == artHash && artBase64.isNotEmpty()) return
        try {
            val maxDim = 192
            val w = bitmap.width
            val h = bitmap.height
            val scaled = if (w > maxDim || h > maxDim) {
                val scale = min(maxDim.toFloat() / w, maxDim.toFloat() / h)
                Bitmap.createScaledBitmap(
                    bitmap,
                    max(1, (w * scale).toInt()),
                    max(1, (h * scale).toInt()),
                    true,
                )
            } else {
                bitmap
            }
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
            artBase64 = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
            artHash = newHash
        } catch (_: Exception) {
        }
    }
}

/**
 * Jembatan aman untuk membaca MediaSession Spotify, mengirim kontrol transport tepat ke Spotify,
 * dan mem-pause Spotify ketika Driving Buddy ditutup.
 */
object SpotifyMediaHelper {
    private val SPOTIFY_PACKAGES = listOf("com.spotify.music", "com.spotify.lite")

    fun isNotificationAccessGranted(context: Context): Boolean {
        return try {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            if (TextUtils.isEmpty(flat)) return false
            val target = ComponentName(context, SpotifyMediaListenerService::class.java).flattenToString()
            val pkg = context.packageName
            flat.split(":").any { item ->
                item.equals(target, ignoreCase = true) ||
                    ComponentName.unflattenFromString(item)?.packageName == pkg
            }
        } catch (_: Exception) {
            false
        }
    }

    fun findActiveSpotifyController(context: Context): MediaController? {
        if (!isNotificationAccessGranted(context)) return null
        return try {
            val mgr = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val comp = ComponentName(context, SpotifyMediaListenerService::class.java)
            val list = mgr.getActiveSessions(comp)
            list.firstOrNull { SPOTIFY_PACKAGES.contains(it.packageName) }
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    fun refreshStateFromMediaSession(context: Context) {
        val controller = findActiveSpotifyController(context) ?: return
        SpotifyStateHolder.updateFromMetadata(controller.packageName, controller.metadata)
        SpotifyStateHolder.updateFromPlaybackState(controller.packageName, controller.playbackState)
    }

    fun getPlaybackSnapshot(context: Context, lastKnownArtHash: String): Map<String, Any?> {
        refreshStateFromMediaSession(context)
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val hasCtrl = findActiveSpotifyController(context) != null
        val isPlaying = if (hasCtrl) {
            SpotifyStateHolder.isPlaying
        } else {
            SpotifyStateHolder.isPlaying && audioManager.isMusicActive
        }
        val includeArt = SpotifyStateHolder.artHash.isNotEmpty() &&
            SpotifyStateHolder.artHash != lastKnownArtHash &&
            SpotifyStateHolder.artBase64.isNotEmpty()

        return hashMapOf(
            "listenerGranted" to isNotificationAccessGranted(context),
            "hasSession" to (hasCtrl || SpotifyStateHolder.hasSession),
            "isPlaying" to isPlaying,
            "isAd" to SpotifyStateHolder.isAd,
            "title" to SpotifyStateHolder.title,
            "artist" to SpotifyStateHolder.artist,
            "album" to SpotifyStateHolder.album,
            "durationMs" to SpotifyStateHolder.durationMs,
            "positionMs" to SpotifyStateHolder.computeCurrentPositionMs(),
            "artUri" to SpotifyStateHolder.artUri,
            "artHash" to SpotifyStateHolder.artHash,
            "artBase64" to if (includeArt) SpotifyStateHolder.artBase64 else "",
        )
    }

    fun sendSpotifyCommand(context: Context, command: String): Boolean {
        val controller = findActiveSpotifyController(context)
        if (controller != null) {
            try {
                val tc = controller.transportControls
                when (command) {
                    "play" -> tc.play()
                    "pause" -> tc.pause()
                    "next" -> tc.skipToNext()
                    "previous" -> tc.skipToPrevious()
                    else -> {
                        if (SpotifyStateHolder.isPlaying) tc.pause() else tc.play()
                    }
                }
                return true
            } catch (_: Exception) {
            }
        }
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val keyCode = when (command) {
            "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        return try {
            audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
            true
        } catch (_: Exception) {
            false
        }
    }

    fun seekSpotify(context: Context, positionMs: Long): Boolean {
        val controller = findActiveSpotifyController(context) ?: return false
        return try {
            controller.transportControls.seekTo(max(0L, positionMs))
            SpotifyStateHolder.basePositionMs = max(0L, positionMs)
            SpotifyStateHolder.lastUpdateElapsedMs = SystemClock.elapsedRealtime()
            true
        } catch (_: Exception) {
            false
        }
    }

    fun pauseSpotify(context: Context) {
        val controller = findActiveSpotifyController(context)
        if (controller != null) {
            try {
                val state = controller.playbackState?.state
                if (state == PlaybackState.STATE_PLAYING || state == PlaybackState.STATE_BUFFERING) {
                    controller.transportControls.pause()
                }
                SpotifyStateHolder.isPlaying = false
                return
            } catch (_: Exception) {
            }
        }
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audioManager.isMusicActive) {
            try {
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PAUSE))
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PAUSE))
            } catch (_: Exception) {
            }
        }
        SpotifyStateHolder.isPlaying = false
    }
}

/**
 * Listener resmi MediaSession & Notifikasi Android untuk membaca lagu aktif Spotify,
 * iklan Spotify, perpindahan lagu rekomendasi, dan timestamp akurat tanpa OAuth tambahan.
 */
class SpotifyMediaListenerService : NotificationListenerService() {
    private var sessionManager: MediaSessionManager? = null
    private var activeSpotifyController: MediaController? = null
    private var spotifyBroadcastReceiver: BroadcastReceiver? = null

    private val controllerCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            val pkg = activeSpotifyController?.packageName ?: "com.spotify.music"
            SpotifyStateHolder.updateFromMetadata(pkg, metadata)
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            val pkg = activeSpotifyController?.packageName ?: "com.spotify.music"
            SpotifyStateHolder.updateFromPlaybackState(pkg, state)
        }

        override fun onSessionDestroyed() {
            SpotifyStateHolder.isPlaying = false
            SpotifyStateHolder.hasSession = false
            activeSpotifyController = null
        }
    }

    private val sessionsListener = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
        attachToSpotifyController(controllers)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        try {
            sessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val comp = ComponentName(this, SpotifyMediaListenerService::class.java)
            sessionManager?.addOnActiveSessionsChangedListener(sessionsListener, comp)
            attachToSpotifyController(sessionManager?.getActiveSessions(comp))
        } catch (_: Exception) {
        }
        registerLegacySpotifyReceiver()
    }

    override fun onListenerDisconnected() {
        detachController()
        try {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsListener)
        } catch (_: Exception) {
        }
        unregisterLegacySpotifyReceiver()
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val pkg = sbn?.packageName ?: return
        if (SpotifyStateHolder.isSpotifyPackage(pkg)) {
            SpotifyStateHolder.updateFromNotification(pkg, sbn.notification)
            SpotifyMediaHelper.refreshStateFromMediaSession(this)
        }
    }

    private fun attachToSpotifyController(controllers: List<MediaController>?) {
        val next = controllers?.firstOrNull { SpotifyStateHolder.isSpotifyPackage(it.packageName) }
        if (next == null) {
            detachController()
            return
        }
        if (activeSpotifyController?.sessionToken == next.sessionToken) {
            SpotifyStateHolder.updateFromMetadata(next.packageName, next.metadata)
            SpotifyStateHolder.updateFromPlaybackState(next.packageName, next.playbackState)
            return
        }
        detachController()
        activeSpotifyController = next
        next.registerCallback(controllerCallback)
        SpotifyStateHolder.updateFromMetadata(next.packageName, next.metadata)
        SpotifyStateHolder.updateFromPlaybackState(next.packageName, next.playbackState)
    }

    private fun detachController() {
        try {
            activeSpotifyController?.unregisterCallback(controllerCallback)
        } catch (_: Exception) {
        }
        activeSpotifyController = null
    }

    private fun registerLegacySpotifyReceiver() {
        if (spotifyBroadcastReceiver != null) return
        val filter = IntentFilter().apply {
            addAction("com.spotify.music.metadatachanged")
            addAction("com.spotify.music.playbackstatechanged")
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                when (intent.action) {
                    "com.spotify.music.metadatachanged" -> {
                        val t = intent.getStringExtra("track") ?: ""
                        val a = intent.getStringExtra("artist") ?: ""
                        val al = intent.getStringExtra("album") ?: ""
                        val len = intent.getIntExtra("length", 0).toLong()
                        if (t.isNotEmpty()) {
                            SpotifyStateHolder.hasSession = true
                            SpotifyStateHolder.packageName = "com.spotify.music"
                            SpotifyStateHolder.title = t
                            SpotifyStateHolder.artist = a
                            SpotifyStateHolder.album = al
                            if (len > 0) SpotifyStateHolder.durationMs = len
                        }
                    }
                    "com.spotify.music.playbackstatechanged" -> {
                        SpotifyStateHolder.hasSession = true
                        SpotifyStateHolder.isPlaying = intent.getBooleanExtra("playing", false)
                        val pos = intent.getIntExtra("playbackPosition", -1).toLong()
                        if (pos >= 0L) {
                            SpotifyStateHolder.basePositionMs = pos
                            SpotifyStateHolder.lastUpdateElapsedMs = SystemClock.elapsedRealtime()
                        }
                    }
                }
            }
        }
        spotifyBroadcastReceiver = receiver
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
        } catch (_: Exception) {
        }
    }

    private fun unregisterLegacySpotifyReceiver() {
        val rec = spotifyBroadcastReceiver ?: return
        spotifyBroadcastReceiver = null
        try {
            unregisterReceiver(rec)
        } catch (_: Exception) {
        }
    }
}
