package com.zhinao.alarm

import org.json.JSONArray
import org.json.JSONObject

/**
 * 闹钟数据模型（Kotlin 侧）
 *
 * 与 Dart 侧 lib/models/alarm.dart 的 toNativeMap() 一一对应。
 * 原生侧持有这份数据的目的：响铃结束后由原生自己算下一次并排程，
 * 不依赖 Flutter 进程是否存活。
 */
data class AlarmModel(
    val id: String,
    val label: String,
    val hour: Int,
    val minute: Int,
    val enabled: Boolean,
    val ruleType: String,
    val weekInterval: Int,
    /** 「每隔 N 天」的 N，取值 2~99。缺失时（旧版存的数据）回落到 2。 */
    val dayInterval: Int,
    val weekdays: List<Int>,
    val anchorDateMillis: Long,
    val monthDays: List<Int>,
    val monthDayFallback: String,
    val snoozeMinutes: Int,
    val maxSnoozeTimes: Int,
    val vibrate: Boolean,
    /** 响铃时是否把系统闹钟音量临时拉到最大。关掉则完全不碰系统音量。 */
    val boostVolume: Boolean,
    val ringDurationSeconds: Int
) {
    /** PendingIntent 的 requestCode，保证每个闹钟互相独立 */
    val requestCode: Int get() = id.hashCode()

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("label", label)
        put("hour", hour)
        put("minute", minute)
        put("enabled", enabled)
        put("ruleType", ruleType)
        put("weekInterval", weekInterval)
        put("dayInterval", dayInterval)
        put("weekdays", JSONArray(weekdays))
        put("anchorDateMillis", anchorDateMillis)
        put("monthDays", JSONArray(monthDays))
        put("monthDayFallback", monthDayFallback)
        put("snoozeMinutes", snoozeMinutes)
        put("maxSnoozeTimes", maxSnoozeTimes)
        put("vibrate", vibrate)
        put("boostVolume", boostVolume)
        put("ringDurationSeconds", ringDurationSeconds)
    }

    companion object {

        /** 从本地 JSON 还原 */
        fun fromJson(o: JSONObject): AlarmModel = AlarmModel(
            id = o.getString("id"),
            label = o.optString("label", ""),
            hour = o.optInt("hour", 7),
            minute = o.optInt("minute", 0),
            enabled = o.optBoolean("enabled", true),
            ruleType = o.optString("ruleType", "daily"),
            weekInterval = o.optInt("weekInterval", 1),
            dayInterval = o.optInt("dayInterval", 2),
            weekdays = o.optJSONArray("weekdays").toIntList(),
            anchorDateMillis = o.optLong("anchorDateMillis", System.currentTimeMillis()),
            monthDays = o.optJSONArray("monthDays").toIntList(),
            monthDayFallback = o.optString("monthDayFallback", "skip"),
            snoozeMinutes = o.optInt("snoozeMinutes", 5),
            maxSnoozeTimes = o.optInt("maxSnoozeTimes", 3),
            vibrate = o.optBoolean("vibrate", true),
            boostVolume = o.optBoolean("boostVolume", true),
            ringDurationSeconds = o.optInt("ringDurationSeconds", 300)
        )

        /**
         * 从 Flutter 传来的 Map 构造。
         * 注意：Flutter 的 int 可能编解码为 Int 或 Long，统一用 Number 接收再转换。
         */
        fun fromFlutterMap(map: Map<*, *>): AlarmModel = AlarmModel(
            id = map["id"] as String,
            label = (map["label"] as? String) ?: "",
            hour = (map["hour"] as Number).toInt(),
            minute = (map["minute"] as Number).toInt(),
            enabled = (map["enabled"] as? Boolean) ?: true,
            ruleType = (map["ruleType"] as? String) ?: "daily",
            weekInterval = (map["weekInterval"] as? Number)?.toInt() ?: 1,
            dayInterval = (map["dayInterval"] as? Number)?.toInt() ?: 2,
            weekdays = (map["weekdays"] as? List<*>)?.mapNotNull {
                (it as? Number)?.toInt()
            } ?: emptyList(),
            anchorDateMillis = (map["anchorDateMillis"] as? Number)?.toLong()
                ?: System.currentTimeMillis(),
            monthDays = (map["monthDays"] as? List<*>)?.mapNotNull {
                (it as? Number)?.toInt()
            } ?: emptyList(),
            monthDayFallback = (map["monthDayFallback"] as? String) ?: "skip",
            snoozeMinutes = (map["snoozeMinutes"] as? Number)?.toInt() ?: 5,
            maxSnoozeTimes = (map["maxSnoozeTimes"] as? Number)?.toInt() ?: 3,
            vibrate = (map["vibrate"] as? Boolean) ?: true,
            boostVolume = (map["boostVolume"] as? Boolean) ?: true,
            ringDurationSeconds = (map["ringDurationSeconds"] as? Number)?.toInt() ?: 300
        )
    }
}

private fun JSONArray?.toIntList(): List<Int> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { i -> if (isNull(i)) null else optInt(i) }
}
