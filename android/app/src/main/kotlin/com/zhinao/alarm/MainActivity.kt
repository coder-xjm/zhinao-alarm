package com.zhinao.alarm

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 与原生交互的入口
 *
 * 通道：
 *   com.zhinao.alarm/control —— Flutter 调原生（同步闹钟、权限检查、跳系统设置）
 *   com.zhinao.alarm/events  —— 原生通知 Flutter（响铃/关闭等事件，用于刷新界面）
 */
class MainActivity : FlutterActivity() {

    private val methodChannelName = "com.zhinao.alarm/control"
    private val eventChannelName = "com.zhinao.alarm/events"

    private var eventSink: EventChannel.EventSink? = null

    /** 本次进程是否已经弹过通知权限申请（避免反复打扰） */
    private var notificationPermissionAsked = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ---------------- 方法通道 ----------------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // 全量同步闹钟并重排
                        "syncAll" -> {
                            syncAll(call.argument("alarms"))
                            result.success(true)
                        }

                        "cancel" -> {
                            call.argument<String>("id")?.let { AlarmScheduler.cancel(this, it) }
                            result.success(null)
                        }

                        "cancelAll" -> {
                            AlarmScheduler.cancelAll(this)
                            result.success(null)
                        }

                        // 立刻全量重排一次（用户在设置页点「立即修复」时用）
                        "rescheduleAll" -> {
                            AlarmScheduler.scheduleAll(this)
                            result.success(true)
                        }

                        // 原生算出的「下次响铃」文案，如「明天 07:30」
                        "nextTriggerText" ->
                            result.success(AlarmScheduler.nextTriggerText(this))

                        // ---- 后台守护（常驻通知保活）----
                        "isKeepAliveEnabled" ->
                            result.success(KeepAliveService.isEnabled(this))
                        "setKeepAlive" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: true
                            KeepAliveService.setEnabled(this, enabled)
                            result.success(enabled)
                        }

                        // ---- 权限与系统设置 ----
                        "canScheduleExact" -> result.success(canScheduleExactAlarms())
                        "requestExactPermission" -> {
                            openExactAlarmSettings()
                            result.success(null)
                        }
                        "isIgnoringBatteryOptimizations" ->
                            result.success(isIgnoringBatteryOptimizations())
                        "requestIgnoreBatteryOptimizations" -> {
                            requestIgnoreBatteryOptimizations()
                            result.success(null)
                        }
                        "openAutoStartSettings" -> {
                            openAutoStartSettings()
                            result.success(null)
                        }
                        "openNotificationSettings" -> {
                            openNotificationSettings()
                            result.success(null)
                        }
                        "openAppSettings" -> {
                            openAppSettings()
                            result.success(null)
                        }

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("NATIVE_ERROR", e.message, null)
                }
            }

        // ---------------- 事件通道（可选，用于原生回调 Flutter） ----------------
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // 兜底：每次进入 App 重排一次，防止排程意外丢失
        AlarmScheduler.scheduleAll(this)
        // 打开 App 时顺手把后台守护服务拉起来（此时 Activity 在前台，允许启动前台服务）
        KeepAliveService.start(this)
    }

    override fun onResume() {
        super.onResume()
        // 从系统设置页返回后，让界面刷新权限状态
        eventSink?.success(mapOf("event" to "resumed"))

        // 每次回到前台都补一遍保险：重排 + 把守护服务叫起来。
        // 用户如果之前用小米的「一键清理」把 App 停掉了，这一下就能完全恢复。
        AlarmScheduler.repairIfNeeded(this)
        KeepAliveService.start(this)

        // Android 13+ 通知权限：没有它，响铃通知和常驻守护通知都不会显示
        ensureNotificationPermission()
    }

    /**
     * 申请通知权限（Android 13+ 才需要）。
     *
     * 这一步很关键：没有通知权限，
     *   · 响铃时的全屏通知弹不出来；
     *   · 后台守护的常驻通知也看不见（前台服务仍在跑，但用户无从确认）。
     */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33) return
        if (notificationPermissionAsked) return

        val granted = runCatching {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
        }.getOrDefault(true)
        if (granted) return

        notificationPermissionAsked = true
        runCatching {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    // ============================================================
    // 同步闹钟
    // ============================================================

    private fun syncAll(raw: Any?) {
        val alarms = (raw as? List<*>)?.mapNotNull { item ->
            (item as? Map<*, *>)?.let { map ->
                runCatching { AlarmModel.fromFlutterMap(map) }.getOrNull()
            }
        } ?: emptyList()

        AlarmStore.saveAll(this, alarms)
        AlarmScheduler.scheduleAll(this)
    }

    // ============================================================
    // 权限检查与跳转
    // ============================================================

    /** 是否拥有精确闹钟权限（Android 12+ 需要用户手动授予） */
    private fun canScheduleExactAlarms(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val manager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        return manager.canScheduleExactAlarms()
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val ok = runCatching {
                startActivity(
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
            }.isSuccess
            if (ok) return
        }
        openAppSettings()
    }

    /** 是否已豁免电池优化（小米上不开这项，闹钟大概率不响） */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        val manager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return manager.isIgnoringBatteryOptimizations(packageName)
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations() {
        val ok = runCatching {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }.isSuccess

        if (ok) return
        // 部分 ROM 不支持上面那个 Intent，退回到电池优化列表页
        runCatching {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }
    }

    /**
     * 打开「自启动管理」页
     * 小米 / 华为 / OPPO / vivo 各自的自启动页组件名不同，逐个尝试，
     * 全部失败则退回到应用详情页。
     */
    private fun openAutoStartSettings() {
        val candidates = listOf(
            // 小米 / 红米 / HyperOS
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            // 小米省电设置（部分版本自启动合并在这里）
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.powercenter.PowerSettings"
            ),
            // 华为 / 荣耀
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            // OPPO / 一加
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            // vivo / iQOO
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            )
        )

        for (componentName in candidates) {
            val intent = Intent().apply {
                component = componentName
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val exists = packageManager
                .resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null
            if (exists && runCatching { startActivity(intent) }.isSuccess) return
        }

        openAppSettings()
    }

    private fun openNotificationSettings() {
        val ok = runCatching {
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }.isSuccess
        if (!ok) openAppSettings()
    }

    private fun openAppSettings() {
        runCatching {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }
    }
}
