package com.zhinao.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 闹钟排程器 —— 整个 App 最关键的一个文件
 *
 * 为什么用 setAlarmClock() 而不是 setExactAndAllowWhileIdle()：
 *   setAlarmClock 是安卓上优先级最高的闹钟通道（系统自带闹钟用的就是它）。
 *   小米 / HyperOS 对它做了白名单豁免，几乎不会被省电策略拦截，
 *   并且状态栏会显示闹钟图标，用户能看见"闹钟已设置"。
 *
 * 排程策略：
 *   每个闹钟只排"下一次"（由 RuleEngine 算出），而不是用 setRepeating。
 *   因为「每隔 2 周的周三」这类规则无法用固定周期表达。
 *   每次响铃触发时（AlarmReceiver 里）立刻排下一次。
 */
object AlarmScheduler {

    const val ACTION_RING = "com.zhinao.alarm.action.RING"
    const val ACTION_SNOOZE_RING = "com.zhinao.alarm.action.SNOOZE_RING"
    const val EXTRA_ALARM_ID = "extra_alarm_id"
    const val EXTRA_IS_SNOOZE = "extra_is_snooze"

    /**
     * 全量重排：先取消全部，再按最新数据重新设置。
     * App 每次改动闹钟、开机、时间被修改后都会调用。
     */
    fun scheduleAll(context: Context) {
        val alarms = AlarmStore.loadAll(context)
        alarms.forEach { cancel(context, it.id) }
        alarms.filter { it.enabled }.forEach { scheduleNext(context, it.id) }
    }

    /** 排下一次（条件一 + 条件二 联合计算） */
    fun scheduleNext(context: Context, alarmId: String, alarm: AlarmModel? = null) {
        val model = alarm ?: AlarmStore.find(context, alarmId) ?: return
        if (!model.enabled) return

        val triggerAt = RuleEngine.nextTrigger(model, System.currentTimeMillis()) ?: return
        setAlarmClock(context, model, triggerAt, isSnooze = false)
    }

    /**
     * 贪睡：额外设一个一次性闹钟。
     * 贪睡不参与条件一判定 —— 用户按了贪睡就要响，跟今天是不是"该响的日子"无关。
     */
    fun scheduleSnooze(context: Context, alarmId: String, minutes: Int) {
        val model = AlarmStore.find(context, alarmId) ?: return
        val triggerAt = System.currentTimeMillis() + minutes * 60_000L
        setAlarmClock(context, model, triggerAt, isSnooze = true)
    }

    /** 取消某个闹钟的排程（正常排程与贪睡排程都取消） */
    fun cancel(context: Context, alarmId: String) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        manager.cancel(buildPendingIntent(context, alarmId, isSnooze = false))
        manager.cancel(buildPendingIntent(context, alarmId, isSnooze = true))
    }

    /** 取消全部排程 */
    fun cancelAll(context: Context) {
        AlarmStore.loadAll(context).forEach { cancel(context, it.id) }
    }

    // ============================================================
    // 内部实现
    // ============================================================

    private fun setAlarmClock(
        context: Context,
        model: AlarmModel,
        triggerAtMillis: Long,
        isSnooze: Boolean
    ) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pendingIntent = buildPendingIntent(context, model.id, isSnooze)

        // 点击状态栏闹钟图标时打开 App
        val showIntent = PendingIntent.getActivity(
            context,
            model.requestCode,
            Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val clockInfo = AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent)

        try {
            manager.setAlarmClock(clockInfo, pendingIntent)
        } catch (e: SecurityException) {
            // 极少数机型没有精确闹钟权限时会抛异常，降级到普通精确闹钟，
            // 能响但可能被省电策略延迟，设置页会提示用户去开权限。
            try {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                )
            } catch (ignored: SecurityException) {
                manager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
        }
    }

    /**
     * 构造广播 PendingIntent。
     * 用不同的 action 区分「正常响铃」和「贪睡响铃」，
     * 因为 Intent 的相等性比较只看 action / data / class，不看 extras。
     */
    private fun buildPendingIntent(
        context: Context,
        alarmId: String,
        isSnooze: Boolean
    ): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = if (isSnooze) ACTION_SNOOZE_RING else ACTION_RING
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_IS_SNOOZE, isSnooze)
        }

        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, alarmId.hashCode(), intent, flags)
    }
}
