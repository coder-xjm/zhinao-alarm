package com.zhinao.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

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
 *
 * 可靠性三层保险（v1.2.0 新增后两层）：
 *   ① 响铃即重排 —— AlarmReceiver 收到广播后先排下一次，再开始响；
 *   ② 常驻守护   —— KeepAliveService 前台服务，被划掉任务时 onTaskRemoved 全量重排；
 *   ③ 定时自检   —— WatchdogReceiver 每 15 分钟补排丢失的排程。
 */
object AlarmScheduler {

    const val ACTION_RING = "com.zhinao.alarm.action.RING"
    const val ACTION_SNOOZE_RING = "com.zhinao.alarm.action.SNOOZE_RING"
    const val EXTRA_ALARM_ID = "extra_alarm_id"
    const val EXTRA_IS_SNOOZE = "extra_is_snooze"

    /** 自检看门狗的广播 action */
    private const val ACTION_WATCHDOG = "com.zhinao.alarm.action.WATCHDOG"

    /** 自检间隔：15 分钟。系统会做批量合并，深睡时实际间隔可能更长，够用。 */
    private const val WATCHDOG_INTERVAL_MS = 15 * 60 * 1000L

    /** 看门狗 PendingIntent 的请求码，取一个和闹钟 id hashCode 不易撞车的值 */
    private const val WATCHDOG_REQUEST_CODE = 20240928

    /**
     * 全量重排：先取消全部，再按最新数据重新设置。
     * App 每次改动闹钟、开机、时间被修改后都会调用。
     */
    fun scheduleAll(context: Context) {
        val alarms = AlarmStore.loadAll(context)
        alarms.forEach { cancel(context, it.id) }
        alarms.filter { it.enabled }.forEach { scheduleNext(context, it.id, it) }

        // 顺手把看门狗挂上，并刷新常驻通知里的「下次响铃」
        scheduleWatchdog(context)
        KeepAliveService.refresh(context)
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

    /**
     * 自检补排：只补齐"丢了的"，不动已经排好的。
     *
     * 判断依据是系统里还存不存在对应的 PendingIntent ——
     * PendingIntent 被系统撤销（省电策略清理、强行停止等）时它会一并消失，
     * 所以「查不到 PendingIntent」就等于「这个闹钟的排程丢了」。
     *
     * @return 本次补排的闹钟个数
     */
    fun repairIfNeeded(context: Context): Int {
        var repaired = 0
        AlarmStore.loadAll(context).filter { it.enabled }.forEach { alarm ->
            if (!isScheduled(context, alarm.id)) {
                scheduleNext(context, alarm.id, alarm)
                repaired++
            }
        }
        return repaired
    }

    /** 某个闹钟是否已在系统里排好（看 PendingIntent 还在不在） */
    fun isScheduled(context: Context, alarmId: String): Boolean =
        buildPendingIntentOrNull(context, alarmId, isSnooze = false) != null

    /** 取消某个闹钟的排程（正常排程与贪睡排程都取消） */
    fun cancel(context: Context, alarmId: String) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return

        listOf(false, true).forEach { isSnooze ->
            // 用 FLAG_NO_CREATE 查找：不存在就不动手，也不留下"空壳" PendingIntent，
            // 否则 isScheduled() 会误判成"已排好"，自检就失效了。
            val pendingIntent = buildPendingIntentOrNull(context, alarmId, isSnooze)
                ?: return@forEach
            runCatching { manager.cancel(pendingIntent) }
            runCatching { pendingIntent.cancel() }
        }
    }

    /** 取消全部排程 */
    fun cancelAll(context: Context) {
        AlarmStore.loadAll(context).forEach { cancel(context, it.id) }
    }

    /**
     * 挂上自检看门狗（一次性闹钟，由 WatchdogReceiver 每次触发时续期）。
     *
     * 用 setAndAllowWhileIdle 而不是 setInexactRepeating：
     *   · 它不需要「精确闹钟」权限，不会因为用户没授权而失效；
     *   · 但它在 Doze（深度睡眠）下依然能唤醒 App，比普通 set() 强得多。
     */
    fun scheduleWatchdog(context: Context) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            WATCHDOG_REQUEST_CODE,
            Intent(context, WatchdogReceiver::class.java).setAction(ACTION_WATCHDOG),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val fireAt = System.currentTimeMillis() + WATCHDOG_INTERVAL_MS

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pendingIntent)
            } else {
                manager.set(AlarmManager.RTC_WAKEUP, fireAt, pendingIntent)
            }
        } catch (ignored: Exception) {
            // 排看门狗失败不影响主流程
        }
    }

    /**
     * 所有启用中的闹钟里，最近的那一次响铃时间，格式化成中文文案。
     * 用于常驻通知「下次响铃：明天 07:30」。
     */
    fun nextTriggerText(context: Context): String {
        val now = System.currentTimeMillis()
        val next = AlarmStore.loadAll(context)
            .filter { it.enabled }
            .mapNotNull { RuleEngine.nextTrigger(it, now) }
            .minOrNull()

        return if (next == null) "暂无启用的闹钟" else "下次响铃：" + formatTrigger(next)
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
     * 构造（或更新）广播 PendingIntent。
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

    /**
     * 只查找、不创建。
     * 返回 null 表示这个闹钟当前在系统里没有任何排程。
     */
    private fun buildPendingIntentOrNull(
        context: Context,
        alarmId: String,
        isSnooze: Boolean
    ): PendingIntent? {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = if (isSnooze) ACTION_SNOOZE_RING else ACTION_RING
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_IS_SNOOZE, isSnooze)
        }

        var flags = PendingIntent.FLAG_NO_CREATE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, alarmId.hashCode(), intent, flags)
    }

    /** 把时间戳格式化成「今天 07:30」「明天 07:30」「10月3日 周五 07:30」 */
    private fun formatTrigger(millis: Long): String {
        val target = Calendar.getInstance().apply { timeInMillis = millis }
        val today = Calendar.getInstance()
        val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }

        val dayText = when {
            isSameDay(target, today) -> "今天"
            isSameDay(target, tomorrow) -> "明天"
            else -> {
                val week = SimpleDateFormat("EEEE", Locale.CHINA).format(Date(millis))
                SimpleDateFormat("M月d日", Locale.CHINA).format(Date(millis)) + " " + week
            }
        }

        return dayText + " " + SimpleDateFormat("HH:mm", Locale.CHINA).format(Date(millis))
    }

    private fun isSameDay(a: Calendar, b: Calendar): Boolean =
        a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
                a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
}
