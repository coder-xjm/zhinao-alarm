package com.zhinao.alarm

import java.util.Calendar

/**
 * 双条件 AND 判定引擎（Kotlin 版）
 *
 * ⚠️ 必须与 Dart 侧 lib/core/date_rule_engine.dart 保持完全一致。
 *
 * 为什么写两份：
 *   Dart 那份负责界面实时预览（"下次响铃：明天 07:00"）；
 *   这份负责实际排程 —— 响铃结束后由原生自己算下一次，
 *   不依赖 Flutter 进程是否存活，这是闹钟能可靠响铃的保证。
 */
object RuleEngine {

    private const val ONE_DAY_MILLIS = 86400000L

    /** 转成 ISO 星期：1=周一 ... 7=周日（Calendar 里周日是 1、周一是 2） */
    private fun isoWeekday(cal: Calendar): Int {
        val dow = cal.get(Calendar.DAY_OF_WEEK)
        return if (dow == Calendar.SUNDAY) 7 else dow - 1
    }

    /** 把时分秒抹掉，只留年月日，避免时分秒干扰判定 */
    private fun normalizeToDay(cal: Calendar) {
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
    }

    // ============================================================
    // 条件一：这一天该不该响
    // ============================================================
    fun matchesDate(alarm: AlarmModel, date: Calendar): Boolean {
        val cal = date.clone() as Calendar
        normalizeToDay(cal)
        val iso = isoWeekday(cal)

        return when (alarm.ruleType) {
            // ---- 每日 ----
            "daily" -> true

            // ---- 工作日：周一至周五 ----
            "workday" -> iso in 1..5

            // ---- 节假日：周六、周日 ----
            "holiday" -> iso == 6 || iso == 7

            // ---- 每隔 N 周的周几 ----
            "weeklyInterval" -> {
                if (!alarm.weekdays.contains(iso)) {
                    false
                } else {
                    val n = if (alarm.weekInterval < 1) 1 else alarm.weekInterval
                    // Kotlin 的 % 对负数返回负值，先转成非负再取模
                    val diff = weekDiff(alarm.anchorDateMillis, cal)
                    ((diff % n) + n) % n == 0
                }
            }

            // ---- 每月 N 号 ----
            "monthlyDay" -> {
                if (alarm.monthDays.isEmpty()) {
                    false
                } else {
                    val dayOfMonth = cal.get(Calendar.DAY_OF_MONTH)
                    when {
                        // 正常命中
                        alarm.monthDays.contains(dayOfMonth) -> true
                        // 小月兜底：如设了 31 号但当前是 2 月
                        alarm.monthDayFallback == "lastDay" -> {
                            val lastDay = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
                            dayOfMonth == lastDay && alarm.monthDays.any { it > lastDay }
                        }
                        else -> false
                    }
                }
            }

            else -> false
        }
    }

    // ============================================================
    // 两个日期相差多少个整周（以周一为每周起点）
    // ============================================================
    private fun weekDiff(anchorMillis: Long, target: Calendar): Int {
        val anchor = Calendar.getInstance().apply { timeInMillis = anchorMillis }
        normalizeToDay(anchor)
        val targetCal = target.clone() as Calendar
        normalizeToDay(targetCal)

        // 各自回退到所在周的周一，再算天数差，必然是 7 的整数倍
        val anchorMonday = (anchor.clone() as Calendar).apply {
            val back = isoWeekday(this) - 1
            add(Calendar.DAY_OF_MONTH, -back)
        }
        val targetMonday = (targetCal.clone() as Calendar).apply {
            val back = isoWeekday(this) - 1
            add(Calendar.DAY_OF_MONTH, -back)
        }
        val diffDays = (targetMonday.timeInMillis - anchorMonday.timeInMillis) / ONE_DAY_MILLIS
        return (diffDays / 7).toInt()
    }

    // ============================================================
    // 条件一 AND 条件二：下一次响铃的时间戳（毫秒）
    // 返回 null 表示未来一年内不会响
    // ============================================================
    fun nextTrigger(alarm: AlarmModel, fromMillis: Long): Long? {
        val today = Calendar.getInstance().apply { timeInMillis = fromMillis }
        normalizeToDay(today)

        for (i in 0..366) {
            val day = (today.clone() as Calendar).apply {
                add(Calendar.DAY_OF_MONTH, i)
            }
            // 条件一不成立 → 看下一天
            if (!matchesDate(alarm, day)) continue

            // 条件一成立 → 拼出条件二的目标时刻
            val fire = (day.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, alarm.hour)
                set(Calendar.MINUTE, alarm.minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            // 必须晚于"现在"，否则继续找下一天
            if (fire.timeInMillis > fromMillis) return fire.timeInMillis
        }
        return null
    }
}
