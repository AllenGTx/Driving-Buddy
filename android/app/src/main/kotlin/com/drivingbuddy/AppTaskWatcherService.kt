package com.drivingbuddy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Menyimpan status apakah Dynamic Island Spotify sedang aktif di sesi ini,
 * agar perbedaan antara menekan tombol Home (tetap main di background)
 * vs menutup aplikasi dari Recents / Back (jeda Spotify & hilangkan Dynamic Island)
 * selalu konsisten.
 */
object SpotifySessionPrefs {
    private const val PREF_NAME = "driving_buddy_spotify_session"
    private const val KEY_ISLAND_ACTIVE = "dynamic_island_active"

    @Volatile
    private var inMemoryActive: Boolean? = null

    fun setDynamicIslandActive(context: Context, active: Boolean) {
        inMemoryActive = active
        try {
            context.applicationContext
                .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ISLAND_ACTIVE, active)
                .apply()
        } catch (_: Exception) {
        }
    }

    fun isDynamicIslandActive(context: Context): Boolean {
        val mem = inMemoryActive
        if (mem != null) return mem
        return try {
            val saved = context.applicationContext
                .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_ISLAND_ACTIVE, false)
            inMemoryActive = saved
            saved
        } catch (_: Exception) {
            false
        }
    }
}

/**
 * Service ringan agar saat pengguna MENUTUP app (swipe dari Recents), `onTaskRemoved`
 * terpanggil meski app sebelumnya sempat diminimize dengan tombol Home.
 * - Tombol Home: `onTaskRemoved` TIDAK dipanggil -> lagu Spotify lanjut putar, Dynamic Island tetap ada.
 * - Tutup App (Swipe Recents): `onTaskRemoved` DIPANGGIL -> Spotify langsung dijeda & status island di-reset!
 */
class AppTaskWatcherService : Service() {
    companion object {
        private const val CHANNEL_ID = "driving_buddy_music_sync"
        private const val NOTIF_ID = 42091
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureForeground()
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (SpotifySessionPrefs.isDynamicIslandActive(applicationContext)) {
            SpotifyMediaHelper.pauseSpotify(applicationContext)
            SpotifySessionPrefs.setDynamicIslandActive(applicationContext, false)
        }
        stopForegroundCompat()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopForegroundCompat()
        super.onDestroy()
    }

    private fun ensureForeground() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Sinkronisasi Musik Spotify",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Menjaga sinkronisasi Spotify dengan Dynamic Island Driving Buddy"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            val notif = builder
                .setContentTitle("Driving Buddy · Spotify Terhubung")
                .setContentText("Musik berjalan di background. Tutup app akan menjeda musik.")
                .setSmallIcon(applicationInfo.icon)
                .setOngoing(true)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIF_ID,
                    notif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIF_ID, notif)
            }
        } catch (_: Exception) {
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
    }
}
