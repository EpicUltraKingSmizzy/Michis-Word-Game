package io.github.michiswordgame.michis_word_game

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/// Runs while this phone is hosting a room, so Android treats the app as
/// "in use" and keeps its network connections (matchmaking server + players)
/// alive when the host switches to a messaging app to share the invite.
/// It doesn't do any work itself; the game keeps running in the main app.
class HostKeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val code = intent?.getStringExtra("code") ?: ""
        val notification = buildNotification(code)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (wakeLock == null) {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            // Keep the CPU awake (not the screen) for at most 3 hours.
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mwg:hosting").apply {
                setReferenceCounted(false)
                acquire(3 * 60 * 60 * 1000L)
            }
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15 limits how long a data-sync service may run.
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The player swiped the app away: the room is gone, so stop.
        stopSelf()
    }

    override fun onDestroy() {
        try {
            wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        super.onDestroy()
    }

    private fun buildNotification(code: String): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Hosting a game", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while your room is open so friends can still join."
                    setShowBadge(false)
                }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(if (code.isEmpty()) "Your room is open" else "Room $code is open")
            .setContentText("Friends can still join while you're in another app.")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "hosting"
        private const val NOTIFICATION_ID = 4242
    }
}
