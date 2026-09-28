package com.zhinao.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 系统事件广播接收器
 *
 * 闹钟的排程存在系统 AlarmManager 里，一旦下面这些事件发生就会全部失效，
 * 必须重新排一遍。漏掉任何一个都会导致「闹钟莫名其妙不响」。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            // 开机完成
            Intent.ACTION_BOOT_COMPLETED,
            // 小米等国产 ROM 的快速开机
            "android.intent.action.QUICKBOOT_POWERON",
            "com.android.quickboot.poweron",
            // App 被覆盖安装 / 升级后
            Intent.ACTION_MY_PACKAGE_REPLACED,
            // 用户手动改了系统时间（会影响周几 / 每月几号的计算）
            Intent.ACTION_TIME_CHANGED,
            // 用户改了时区
            Intent.ACTION_TIMEZONE_CHANGED,
            // 用户改了日期
            Intent.ACTION_DATE_CHANGED -> {
                AlarmScheduler.scheduleAll(context)
            }
        }
    }
}
