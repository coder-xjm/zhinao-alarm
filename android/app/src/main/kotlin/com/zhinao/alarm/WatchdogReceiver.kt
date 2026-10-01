package com.zhinao.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 闹钟自检看门狗
 *
 * 每 15 分钟醒一次（用 setAndAllowWhileIdle 排，深睡状态下也能叫醒），做三件事：
 *   1. 给自己续期 —— 这个闹钟是一次性的，不续期就只响一次；
 *   2. 逐个检查启用中的闹钟是否还挂在系统里，丢了的立刻补排；
 *   3. 顺手刷新常驻通知里的「下次响铃」文案。
 *
 * 它兜住的是这些意外：系统因为省电策略清掉了排程、时区/时间被改、
 * App 被系统回收后重新拉起等等。
 *
 * ⚠️ 边界：如果用户对 App 点了「强行停止」，或者小米「一键清理」把它停掉了，
 *    看门狗本身也会被系统一并撤销。这种情况唯一能恢复的办法，
 *    就是用户重新打开一次 App（打开时 MainActivity 会全量重排）。
 */
class WatchdogReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // 1. 先续期，保证下 15 分钟还会被叫醒
        AlarmScheduler.scheduleWatchdog(context)

        // 2. 补排丢失的闹钟（返回值是补排条数，这里不展示，仅供将来排查）
        AlarmScheduler.repairIfNeeded(context)

        // 3. 刷新常驻通知（服务没在跑时会尝试拉起；后台被限制则静默跳过）
        KeepAliveService.refresh(context)
    }
}
