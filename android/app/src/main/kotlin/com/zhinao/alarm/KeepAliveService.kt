package com.zhinao.alarm

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
 * 后台守护服务（常驻前台服务）
 *
 * ── 为什么必须有它 ────────────────────────────────────────────
 * 小米 / HyperOS 对第三方 App 的后台管控极严。用户「从最近任务里划掉智闹」时，
 * 对没有前台服务、又不在白名单里的 App，MIUI 会直接把它停掉
 * （等同于系统设置里的「强行停止」）。App 一旦进入停止状态：
 *   · 系统会**撤销它注册过的全部闹钟**；
 *   · 之后连开机广播、时间变更广播都不再发给它。
 * 表现就是「一关 App，闹钟就永远不响了，而且不会自己恢复」。
 *
 * 前台服务带常驻通知，在系统眼里属于「正在运行的 App」：
 *   · 划掉最近任务时，通常不会被判定为强行停止，闹钟得以保留；
 *   · 即便被划掉，onTaskRemoved() 也会被回调 —— 我们在那里立刻把
 *     全部闹钟重新排一遍，等于给自己上了一份保险。
 *
 * 通知内容会显示「下一次响铃时间」，用户一眼就能确认闹钟是否还挂着。
 * 用户可在设置页一键关闭（默认开启）。
 */
class KeepAliveService : Service() {

    companion object {
        private const val CHANNEL_ID = "zhinao_keepalive"
        private const val NOTIFICATION_ID = 1000

        private const val PREF = "zhinao_keepalive_pref"
        private const val KEY_ENABLED = "keepalive_enabled"

        private const val ACTION_START = "com.zhinao.alarm.action.KEEPALIVE_START"
        private const val ACTION_REFRESH = "com.zhinao.alarm.action.KEEPALIVE_REFRESH"

        /** Android 14（API 34）起，前台服务必须声明具体类型 */
        private const val API_34 = 34

        /** 用户是否开启了后台守护，默认开启 */
        fun isEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, true)

        /** 开启 / 关闭后台守护，并把服务跟着启停 */
        fun setEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_ENABLED, enabled).apply()

            if (enabled) start(context) else stopKeepAlive(context)
        }

        /** 启动守护服务（开关关闭时什么都不做） */
        fun start(context: Context) {
            if (!isEnabled(context)) return
            deliver(context, Intent(context, KeepAliveService::class.java).setAction(ACTION_START))
        }

        /**
         * 只刷新通知文案（"下次响铃：明天 07:30"）。
         * 服务没在跑时这个调用会顺带把它拉起来；后台被禁止启动时静默失败。
         */
        fun refresh(context: Context) {
            if (!isEnabled(context)) return
            deliver(context, Intent(context, KeepAliveService::class.java).setAction(ACTION_REFRESH))
        }

        /** 停止守护服务（用户关掉开关时调用） */
        fun stopKeepAlive(context: Context) {
            runCatching {
                context.stopService(Intent(context, KeepAliveService::class.java))
            }
        }

        /**
         * 投递意图。
         *
         * Android 12+ 会限制「从后台启动前台服务」，失败时静态放弃 ——
         * 真正需要它生效的场景（打开 App、开机、闹钟触发、划掉任务）
         * 都是被系统放行的，不会走到失败分支。
         */
        private fun deliver(context: Context, intent: Intent) {
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 开关被关掉了，或服务被系统重启但用户已关闭守护 → 干净退出。
        // 注意：这里必须先 stopForeground 再 stopSelf，
        // 否则 startForegroundService 起的服务没走 startForeground 会抛异常。
        if (!isEnabled(this)) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        // 常驻通知 + 一次自检补排
        showNotification()
        AlarmScheduler.scheduleWatchdog(this)
        AlarmScheduler.repairIfNeeded(this)

        return START_STICKY
    }

    /**
     * 用户把 App 从最近任务里划掉了。
     *
     * 这是本服务存在的最重要的理由：小米在这一步很可能连带把闹钟也撤了，
     * 所以这里立刻把全部闹钟重新排一遍 —— 用户第二天照样能听到响铃。
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        AlarmScheduler.scheduleAll(this)
        AlarmScheduler.scheduleWatchdog(this)
        showNotification()
        super.onTaskRemoved(rootIntent)
    }

    // ============================================================
    // 通知
    // ============================================================

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "后台守护",
            // LOW：有通知但不发声、不震动，纯粹是「我很稳」的状态指示
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "常驻通知，显示下一次闹钟时间，防止被系统清理掉排程"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun showNotification() {
        createChannel()

        val nextText = AlarmScheduler.nextTriggerText(this)

        // 点通知回到 App 主界面
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("智闹守护中")
            .setContentText(nextText)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "$nextText\n\n这条通知常驻时，划掉智闹也不会丢闹钟。"
                )
            )
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .setSilent(true)
            .setContentIntent(contentIntent)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= API_34) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (ignored: Exception) {
            // 个别 ROM 拒绝特殊类型的前台服务，降级为不带类型再试一次
            runCatching { startForeground(NOTIFICATION_ID, notification) }
                .onFailure { stopSelf() }
        }
    }

    private fun stopForegroundCompat() {
        // minSdk = 24，STOP_FOREGROUND_REMOVE 从 API 24 起可用，无需版本判断
        runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
    }
}
