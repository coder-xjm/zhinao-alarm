package com.zhinao.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

/**
 * 响铃前台服务
 *
 * 为什么必须是「前台服务」而不是普通 Service：
 *   前台服务有常驻通知，系统不会轻易回收，能在小米省电策略下争取到执行时间。
 *
 * 职责：
 *   播放铃声（循环）、震动、发全屏通知、拉起全屏响铃页、到时自动停。
 */
class RingService : Service() {

    companion object {
        private const val CHANNEL_ID = "zhinao_alarm_ring"
        private const val NOTIFICATION_ID = 1001
        private const val PREF_SNOOZE = "zhinao_snooze_count"

        const val ACTION_STOP = "com.zhinao.alarm.action.STOP_RING"
        const val ACTION_SNOOZE = "com.zhinao.alarm.action.DO_SNOOZE"

        /** 响铃页 / 通知栏点「关闭」 */
        fun stop(context: Context) {
            val intent = Intent(context, RingService::class.java).setAction(ACTION_STOP)
            startCompat(context, intent)
        }

        /** 响铃页 / 通知栏点「贪睡」 */
        fun snooze(context: Context) {
            val intent = Intent(context, RingService::class.java).setAction(ACTION_SNOOZE)
            startCompat(context, intent)
        }

        /** 这个闹钟还能不能再贪睡（受「最多贪睡次数」限制） */
        fun canSnooze(context: Context, alarmId: String): Boolean {
            val alarm = AlarmStore.find(context, alarmId) ?: return false
            return snoozeCount(context, alarmId) < alarm.maxSnoozeTimes
        }

        fun snoozeCount(context: Context, alarmId: String): Int =
            context.getSharedPreferences(PREF_SNOOZE, Context.MODE_PRIVATE)
                .getInt(alarmId, 0)

        /** 贪睡次数 +1 */
        fun increaseSnooze(context: Context, alarmId: String) {
            val prefs = context.getSharedPreferences(PREF_SNOOZE, Context.MODE_PRIVATE)
            prefs.edit().putInt(alarmId, snoozeCount(context, alarmId) + 1).apply()
        }

        /** 新的一轮响铃开始，贪睡次数清零 */
        fun resetSnooze(context: Context, alarmId: String) {
            context.getSharedPreferences(PREF_SNOOZE, Context.MODE_PRIVATE)
                .edit().putInt(alarmId, 0).apply()
        }

        private fun startCompat(context: Context, intent: Intent) {
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }
    }

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private var alarmId: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 服务被系统重启时 intent 为空，直接退出
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        when (intent.action) {
            // ---------- 用户点了「关闭」 ----------
            ACTION_STOP -> {
                val id = alarmId ?: intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID)
                stopRinging()
                id?.let {
                    RingService.resetSnooze(this, it)
                    AlarmScheduler.scheduleNext(this, it)
                }
                stopSelf()
                return START_NOT_STICKY
            }

            // ---------- 用户点了「贪睡」 ----------
            ACTION_SNOOZE -> {
                val id = alarmId ?: intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID)
                val minutes = id?.let { AlarmStore.find(this, it)?.snoozeMinutes } ?: 5
                stopRinging()
                if (id != null) {
                    RingService.increaseSnooze(this, id)
                    // 贪睡是一次性的，不参与条件一判定
                    AlarmScheduler.scheduleSnooze(this, id, minutes)
                }
                stopSelf()
                return START_NOT_STICKY
            }
        }

        // ---------- 正常响铃 ----------
        val id = intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID)
        val alarm = id?.let { AlarmStore.find(this, it) }

        if (alarm == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        alarmId = alarm.id

        showForegroundNotification(alarm)
        startSound()
        startVibration(alarm)
        launchRingActivity(alarm)
        scheduleAutoStop(alarm)

        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopRinging()
        super.onDestroy()
    }

    // ============================================================
    // 通知
    // ============================================================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "闹钟响铃",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "闹钟到点时的响铃提醒"
            // 声音和震动由 MediaPlayer / Vibrator 负责，这里关掉避免重复
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun showForegroundNotification(alarm: AlarmModel) {
        val ringIntent = PendingIntent.getActivity(
            this,
            alarm.requestCode,
            Intent(this, RingActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                )
                putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = PendingIntent.getService(
            this,
            alarm.requestCode + 1,
            Intent(this, RingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val snoozeIntent = PendingIntent.getService(
            this,
            alarm.requestCode + 2,
            Intent(this, RingService::class.java).setAction(ACTION_SNOOZE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(alarm.label.ifEmpty { "闹钟" })
            .setContentText("${alarm.hour.padZero()}:${alarm.minute.padZero()}")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // 全屏 Intent：锁屏状态下直接弹出响铃页
            .setFullScreenIntent(ringIntent, true)
            .setContentIntent(ringIntent)
            .addAction(0, "贪睡", snoozeIntent)
            .addAction(0, "关闭", stopIntent)

        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    // ============================================================
    // 声音 / 震动
    // ============================================================

    private fun startSound() {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: return

        try {
            // 把闹钟音量拉到最大：闹钟的意义就是必须被听见
            (getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.let { am ->
                val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                am.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
            }

            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@RingService, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            // 铃声播放失败不影响震动和界面，不中断响铃流程
        }
    }

    private fun startVibration(alarm: AlarmModel) {
        if (!alarm.vibrate) return

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            (getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
        }

        // 响 0.8 秒、停 0.5 秒，循环
        val pattern = longArrayOf(0, 800, 500)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        }
    }

    private fun stopRinging() {
        runCatching {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        }
        player = null

        runCatching { vibrator?.cancel() }
        vibrator = null
    }

    // ============================================================
    // 拉起响铃页 / 自动停止
    // ============================================================

    private fun launchRingActivity(alarm: AlarmModel) {
        val intent = Intent(this, RingActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
            )
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id)
        }
        // Android 10+ 后台启动 Activity 受限，失败也没关系 ——
        // 上面的全屏通知会兜底弹出响铃页
        runCatching { startActivity(intent) }
    }

    /** 到设定时长自动停止，避免闹钟一直响到没电 */
    private fun scheduleAutoStop(alarm: AlarmModel) {
        handler.removeCallbacksAndMessages(null)
        val delayMillis = alarm.ringDurationSeconds.coerceAtLeast(10) * 1000L

        handler.postDelayed({
            val id = alarmId
            stopRinging()
            if (id != null) {
                RingService.resetSnooze(this, id)
                AlarmScheduler.scheduleNext(this, id)
            }
            stopSelf()
        }, delayMillis)
    }
}

/** 数字补零：7 → "07" */
private fun Int.padZero(): String = toString().padStart(2, '0')
