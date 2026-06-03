package com.thienhai.tropia_mobile_app_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service kept alive for the whole RTMP publish session.
 *
 * Ported from the standalone tropia livestream app (lib/livestream module).
 *
 * Why: Android 8+ kills background activities aggressively. Without a
 * foreground service, locking the screen or switching apps for >5 min
 * tears down `apivideo_live_stream`'s camera/RTMP socket, the SRS
 * server fires on_unpublish, and buyers see "stream ended" even though
 * the host hasn't pressed "Kết thúc Live". A foreground service with a
 * visible notification opts out of that kill: same lifecycle Spotify
 * uses to keep music playing when the screen is off.
 *
 * Started from Flutter via MethodChannel("tropia/live_stream") just
 * before apivideo.startStreaming(), stopped from _stopLive. The service
 * itself doesn't touch the camera or RTMP socket — apivideo still owns
 * those. We exist purely to anchor the process priority.
 */
class LiveStreamForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "tropia_live_stream"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.thienhai.tropia_mobile_app_android.action.START_LIVE"
        const val ACTION_STOP = "com.thienhai.tropia_mobile_app_android.action.STOP_LIVE"
        const val EXTRA_TITLE = "title"

        fun start(context: Context, title: String) {
            val intent = Intent(context, LiveStreamForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, LiveStreamForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Livestream Tropia"
                startForegroundWithType(title)
            }
        }
        // START_STICKY would restart the service after a crash, but we
        // don't want that — if apivideo died there's no RTMP socket
        // for us to "anchor" anymore. Let Flutter explicitly restart.
        return START_NOT_STICKY
    }

    private fun startForegroundWithType(title: String) {
        ensureChannel()
        val notification = buildNotification(title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+: must declare which foreground service types
            // we're using so the OS can audit them. Camera + microphone
            // because apivideo holds both.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Livestream đang phát",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Hiển thị khi bạn đang livestream"
            setShowBadge(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String): Notification {
        val openAppIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        val pendingIntent = openAppIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("Đang livestream — chạm để quay lại app")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }
}
