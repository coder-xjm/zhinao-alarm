import '../models/alarm.dart';

/// ============================================================
/// 核心引擎：双条件 AND 判定的 Dart 实现
///
/// 这个文件是 App 的大脑，负责回答两个问题：
///   1. 某一天，条件一（日期规则）成立吗？      → matchesDate()
///   2. 下一次「两个条件同时满足」是什么时候？  → nextTrigger()
///
/// ⚠️ 重要：Android 原生侧 Kotlin 里有一份逻辑完全一致的实现
///    （RuleEngine.kt）。Dart 这份负责界面预览，Kotlin 那份负责实际
///    排程。两边必须同步修改，判定规则见需求文档附录 A。
/// ============================================================
class DateRuleEngine {
  const DateRuleEngine._();

  /// ------------------------------------------------------------
  /// 条件一判定：给定日期，这个闹钟的日期规则成立吗？
  /// ------------------------------------------------------------
  static bool matchesDate(Alarm alarm, DateTime date) {
    // 归一化到当天 00:00，避免时分秒干扰
    final d = DateTime(date.year, date.month, date.day);

    switch (alarm.ruleType) {
      // ---- 1. 每日：永远成立 ----
      case DateRuleType.daily:
        return true;

      // ---- 2. 工作日：周一~周五 ----
      case DateRuleType.workday:
        return d.weekday >= DateTime.monday && d.weekday <= DateTime.friday;

      // ---- 3. 节假日：周六、周日 ----
      case DateRuleType.holiday:
        return d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

      // ---- 4. 每隔 N 周的周几 ----
      case DateRuleType.weeklyInterval:
        // 先看星期几有没有被选中
        if (!alarm.weekdays.contains(d.weekday)) return false;
        // 再看周差能不能被 N 整除
        final n = alarm.weekInterval < 1 ? 1 : alarm.weekInterval;
        return weekDiff(alarm.anchorDate, d) % n == 0;

      // ---- 5. 每月 N 号 ----
      case DateRuleType.monthlyDay:
        if (alarm.monthDays.isEmpty) return false;
        // 正常命中
        if (alarm.monthDays.contains(d.day)) return true;
        // 小月兜底：如设了 31 号但当前是 2 月
        if (alarm.monthDayFallback == MonthDayFallback.lastDay) {
          final lastDayOfMonth = DateTime(d.year, d.month + 1, 0).day;
          // 只有当天正好是本月最后一天，且用户选的日期里存在「本月装不下」的日期，才顺延
          return d.day == lastDayOfMonth &&
              alarm.monthDays.any((day) => day > lastDayOfMonth);
        }
        return false;
    }
  }

  /// ------------------------------------------------------------
  /// 计算两个日期相差多少个「整周」（以周一为每周起点）
  ///
  /// 例：锚点 2026-09-28（周一），目标 2026-10-12（周一）→ 相差 2 周
  /// Dart 的 % 对负数同样返回非负结果，所以目标早于锚点时结果依然正确。
  /// ------------------------------------------------------------
  static int weekDiff(DateTime anchor, DateTime target) {
    final anchorMonday =
        _toDateOnly(anchor).subtract(Duration(days: anchor.weekday - 1));
    final targetMonday =
        _toDateOnly(target).subtract(Duration(days: target.weekday - 1));
    return targetMonday.difference(anchorMonday).inDays ~/ 7;
  }

  /// ------------------------------------------------------------
  /// 计算下一次响铃的完整时刻（条件一 AND 条件二）
  ///
  /// 从 [from] 时刻起向后逐日扫描，最多 366 天。
  /// 返回 null 表示未来一年内不会再响（理论上不会发生）。
  /// ------------------------------------------------------------
  static DateTime? nextTrigger(Alarm alarm, DateTime from) {
    final today = _toDateOnly(from);

    for (var i = 0; i <= 366; i++) {
      final day = today.add(Duration(days: i));
      final normalized = _toDateOnly(day);

      // 条件一不成立 → 跳到下一天
      if (!matchesDate(alarm, normalized)) continue;

      // 条件一成立 → 拼出条件二的目标时刻
      final fireAt = DateTime(
        normalized.year,
        normalized.month,
        normalized.day,
        alarm.hour,
        alarm.minute,
      );

      // 必须晚于「现在」才算下一次（避免设置瞬间立刻响）
      if (fireAt.isAfter(from)) return fireAt;
    }
    return null;
  }

  /// ------------------------------------------------------------
  /// 未来若干次响铃时刻，用于编辑页做「未来 3 次响铃」预览
  /// ------------------------------------------------------------
  static List<DateTime> upcomingTriggers(Alarm alarm,
      {int count = 3, DateTime? from}) {
    final result = <DateTime>[];
    var cursor = from ?? DateTime.now();

    for (var i = 0; i < count; i++) {
      final next = nextTrigger(alarm, cursor);
      if (next == null) break;
      result.add(next);
      // 从这次之后一秒继续找下一次
      cursor = next.add(const Duration(seconds: 1));
    }
    return result;
  }

  /// ------------------------------------------------------------
  /// 把「下次响铃」翻译成人话：今天 / 明天 / 周三 / 10月15日
  /// ------------------------------------------------------------
  static String describeNext(DateTime? next) {
    if (next == null) return '不会再响';

    final now = DateTime.now();
    final today = _toDateOnly(now);
    final target = _toDateOnly(next);
    final dayDiff = target.difference(today).inDays;

    final time =
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';

    if (dayDiff == 0) return '今天 $time';
    if (dayDiff == 1) return '明天 $time';
    if (dayDiff == 2) return '后天 $time';
    if (dayDiff < 7) return '${Alarm.weekdayName(next.weekday)} $time';
    return '${next.month}月${next.day}日 $time';
  }

  /// 未来 3 次预览用：完整描述，如 "10月12日 周一 07:00"
  static String describeFull(DateTime d) =>
      '${d.month}月${d.day}日 ${Alarm.weekdayName(d.weekday)} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// 去掉时分秒，只留年月日
  static DateTime _toDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
