package com.zhinao.alarm

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 全屏响铃页（原生 Activity）
 *
 * 为什么不用 Flutter 页面来响铃：
 *   响铃是闹钟唯一的使命，必须最短路径、最少依赖。原生 Activity 启动快、
 *   内存占用小，即使 Flutter 引擎已被系统回收也照样能弹出来。
 *
 * 关键能力：
 *   · 在锁屏上直接显示（setShowWhenLocked）
 *   · 自动点亮屏幕（setTurnScreenOn + FLAG_KEEP_SCREEN_ON）
 *   · 深色界面，刚睡醒时不刺眼
 */
class RingActivity : Activity() {

    private var alarmId: String? = null
    private var alarm: AlarmModel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        alarmId = intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID)
        alarm = alarmId?.let { AlarmStore.find(this, it) }

        setupLockScreenWindow()
        setContentView(buildContentView())
    }

    /** 让页面能盖在锁屏上，并自动点亮屏幕 */
    private fun setupLockScreenWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /** 返回键不生效：必须明确选择「贪睡」或「关闭」 */
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // 故意留空
    }

    // ============================================================
    // 界面（用代码构建，省掉一份 XML 布局文件）
    // ============================================================

    private fun buildContentView(): View {
        val density = resources.displayMetrics.density
        val dp = { v: Int -> (v * density).toInt() }

        val model = alarm
        val label = model?.label.orEmpty()
        val snoozeMinutes = model?.snoozeMinutes ?: 5
        val canSnooze = alarmId?.let { RingService.canSnooze(this, it) } ?: false

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.parseColor("#0A0A12"))
            setPadding(dp(28), dp(72), dp(28), dp(56))
        }

        // ---------- 目标时间（条件二） ----------
        root.addView(
            TextView(this).apply {
                text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
                setTextColor(Color.WHITE)
                textSize = 64f
                typeface = Typeface.create("sans-serif-thin", Typeface.NORMAL)
                gravity = Gravity.CENTER
            }
        )

        // ---------- 标签 ----------
        if (label.isNotEmpty()) {
            root.addView(
                TextView(this).apply {
                    text = label
                    setTextColor(Color.parseColor("#C3C3D2"))
                    textSize = 20f
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(10) }
            )
        }

        // ---------- 日期 ----------
        root.addView(
            TextView(this).apply {
                text = SimpleDateFormat("M月d日 EEEE", Locale.CHINA).format(Date())
                setTextColor(Color.parseColor("#71718A"))
                textSize = 14f
                gravity = Gravity.CENTER
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(10) }
        )

        // ---------- 触发说明，让用户理解为什么今天响了 ----------
        root.addView(
            TextView(this).apply {
                text = "条件一（${ruleText(model?.ruleType)}）与条件二（${model?.hour?.let { h -> h.toString().padStart(2, '0') } ?: "--"}:${model?.minute?.let { m -> m.toString().padStart(2, '0') } ?: "--"}）同时满足"
                setTextColor(Color.parseColor("#4E4E63"))
                textSize = 12f
                gravity = Gravity.CENTER
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(20) }
        )

        // ---------- 撑开中间空白 ----------
        root.addView(
            Space(this),
            LinearLayout.LayoutParams(0, 0, 1f)
        )

        // ---------- 贪睡按钮 ----------
        if (canSnooze) {
            root.addView(
                roundedButton(
                    text = "贪睡 $snoozeMinutes 分钟",
                    bgColor = Color.parseColor("#23233A"),
                    textColor = Color.parseColor("#E4E4F0")
                ) {
                    RingService.snooze(this)
                    finish()
                }
            )
        }

        // ---------- 关闭按钮 ----------
        root.addView(
            roundedButton(
                text = "关闭",
                bgColor = Color.parseColor("#6C7BF5"),
                textColor = Color.WHITE
            ) {
                RingService.stop(this)
                finish()
            },
            LinearLayout.LayoutParams(dp(240), dp(58)).apply { topMargin = dp(14) }
        )

        return root
    }

    /**
     * 造一个圆角按钮
     *
     * 注意：参数不能命名为 background。TextView 上有个同名属性，函数参数会
     * 把它遮蔽掉，于是 `background = ...` 会被编译器当成给 Int 参数赋值，
     * 报 "Val cannot be reassigned" + "Type mismatch"。
     * 这里统一改用 bgColor，并用 setBackground() 显式调用。
     */
    private fun roundedButton(
        text: String,
        bgColor: Int,
        textColor: Int,
        onClick: () -> Unit
    ): TextView {
        val density = resources.displayMetrics.density
        val dp = { v: Int -> (v * density).toInt() }

        return TextView(this).apply {
            this.text = text
            setTextColor(textColor)
            textSize = 17f
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            // 圆角背景：用 setBackground 显式设置，避免与同名字段混淆
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(29).toFloat()
                setColor(bgColor)
            }
            setBackground(bg)
            layoutParams = LinearLayout.LayoutParams(dp(240), dp(58))
            setOnClickListener { onClick() }
        }
    }

    /** 规则类型转中文，用于响铃页说明 */
    private fun ruleText(ruleType: String?): String = when (ruleType) {
        "daily" -> "每日"
        "workday" -> "工作日"
        "holiday" -> "节假日"
        "weeklyInterval" -> "每隔几周的周几"
        "monthlyDay" -> "每月几号"
        else -> "日期规则"
    }
}
