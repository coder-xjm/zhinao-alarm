package com.zhinao.alarm

import android.content.Context
import org.json.JSONArray

/**
 * 原生侧的闹钟存储（SharedPreferences + JSON）
 *
 * 为什么要单独存一份：
 *   响铃结束后、开机广播后，原生需要独立算出"下一次"并排程，
 *   这时候 Flutter 引擎很可能没启动。把数据放在 SharedPreferences
 *   里可以随时读取，不受进程存活影响。
 *
 * 与 Dart 侧的 SQLite 通过 syncAll 保持同步，Dart 侧是数据源。
 */
object AlarmStore {

    private const val PREF_NAME = "zhinao_alarm_store"
    private const val KEY_ALARMS = "alarms"

    /** 全量覆盖保存 */
    fun saveAll(context: Context, alarms: List<AlarmModel>) {
        val array = JSONArray()
        alarms.forEach { array.put(it.toJson()) }
        prefs(context).edit().putString(KEY_ALARMS, array.toString()).apply()
    }

    /** 读取全部闹钟 */
    fun loadAll(context: Context): List<AlarmModel> {
        val raw = prefs(context).getString(KEY_ALARMS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { i ->
                runCatching { AlarmModel.fromJson(array.getJSONObject(i)) }.getOrNull()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** 按 id 查单个闹钟 */
    fun find(context: Context, id: String): AlarmModel? =
        loadAll(context).firstOrNull { it.id == id }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
}
