package com.zhinao.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 闹钟到点广播接收器
 *
 * 做两件事：
 *   1. 立刻排"下一次" —— 放在最前面，保证即使响铃环节出问题，
 *      下一个周期的闹钟也已经安排好了（闹钟 App 的自愈设计）。
 *   2. 启动前台服务开始响铃。
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID) ?: return
        val isSnooze = intent.getBooleanExtra(AlarmScheduler.EXTRA_IS_SNOOZE, false)

        // ---- 1. 先排下一次（贪睡触发的情况不需要重排，下次排程在按贪睡时已保留）----
        if (!isSnooze) {
            AlarmScheduler.scheduleNext(context, alarmId)
        }

        // ---- 2. 启动响铃前台服务 ----
        val serviceIntent = Intent(context, RingService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmScheduler.EXTRA_IS_SNOOZE, isSnooze)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            // 后台启动服务被限制时的兜底：直接拉起响铃页面，
            // 由页面自行播放（多见于国产 ROM 的极端省电模式）
            val activityIntent = Intent(context, RingActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                )
                putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
            }
            runCatching { context.startActivity(activityIntent) }
        }
    }
}
