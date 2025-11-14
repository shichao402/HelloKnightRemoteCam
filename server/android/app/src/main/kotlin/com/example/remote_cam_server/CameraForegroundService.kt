package com.example.remote_cam_server

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class CameraForegroundService : Service() {
    private val TAG = "CameraForegroundService"
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "camera_preview_channel"

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "前台服务已创建")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "前台服务已启动")
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY // 服务被系统杀死后自动重启
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "前台服务已销毁")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "相机预览服务",
                NotificationManager.IMPORTANCE_LOW // 低优先级，不发出声音
            ).apply {
                description = "保持相机预览流在后台运行"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("远程相机服务")
            .setContentText("相机预览流正在运行")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
            .setOngoing(true) // 持续通知
            .setPriority(NotificationCompat.PRIORITY_LOW) // 低优先级
            .build()
    }

    companion object {
        fun startService(context: Context) {
            val intent = Intent(context, CameraForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, CameraForegroundService::class.java)
            context.stopService(intent)
        }
    }
}

