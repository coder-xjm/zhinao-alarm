import 'dart:convert';

/// ============================================================
/// 条件一的 5 种日期规则类型
/// ============================================================
enum DateRuleType {
  daily('每日'),
  workday('工作日'),
  holiday('节假日'),
  weeklyInterval('每隔几周的周几'),
  monthlyDay('每月几号');

  const DateRuleType(this.label);

  /// 中文展示名
  final String label;

  static DateRuleType fromName(String name) => DateRuleType.values
      .firstWhere((e) => e.name == name, orElse: () => DateRuleType.daily);
}

/// ============================================================
/// 「每月几号」遇到小月（如 2 月没有 31 号）时的处理方式
/// ============================================================
enum MonthDayFallback {
  skip('跳过本月'),
  lastDay('顺延到当月最后一天');

  const MonthDayFallback(this.label);

  final String label;

  static MonthDayFallback fromName(String name) =>
      MonthDayFallback.values.firstWhere((e) => e.name == name,
          orElse: () => MonthDayFallback.skip);
}

/// ============================================================
/// 闹钟数据模型
///
/// 一个闹钟 = 条件一（日期规则）+ 条件二（目标时间）+ 响铃行为
/// 两者同时满足才会触发（AND 逻辑），见 DateRuleEngine
/// ============================================================
class Alarm {
  Alarm({
    String? id,
    this.label = '',
    this.hour = 7,
    this.minute = 0,
    this.enabled = true,
    this.ruleType = DateRuleType.workday,
    this.weekInterval = 1,
    List<int>? weekdays,
    DateTime? anchorDate,
    List<int>? monthDays,
    this.monthDayFallback = MonthDayFallback.skip,
    this.snoozeMinutes = 5,
    this.maxSnoozeTimes = 3,
    this.vibrate = true,
    this.ringDurationSeconds = 300,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        weekdays = weekdays ?? <int>[1, 2, 3, 4, 5],
        anchorDate = anchorDate ?? DateTime.now(),
        monthDays = monthDays ?? <int>[1];

  /// 唯一标识
  String id;

  /// 标签，如「早起」「交房租」
  String label;

  /// ===== 条件二：目标时间 =====
  int hour;
  int minute;

  /// 是否启用（关闭后不参与排程）
  bool enabled;

  /// ===== 条件一：日期规则 =====
  DateRuleType ruleType;

  /// 「每隔 N 周」的 N，取值 1~8
  int weekInterval;

  /// 「每隔 N 周的周几」里选中的星期，1=周一 ... 7=周日
  List<int> weekdays;

  /// 周差计算锚点（以创建当周为第 1 周）
  DateTime anchorDate;

  /// 「每月几号」里选中的日期，1~31
  List<int> monthDays;

  /// 小月无此日时的处理方式
  MonthDayFallback monthDayFallback;

  /// ===== 响铃行为 =====
  /// 贪睡时长（分钟）
  int snoozeMinutes;

  /// 最多贪睡次数
  int maxSnoozeTimes;

  /// 是否震动
  bool vibrate;

  /// 响铃时长（秒），到点自动停
  int ringDurationSeconds;

  /// 条件二的中文展示，如 "07:00"
  String get timeText =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// 条件一的中文摘要，用于列表展示
  String get ruleSummary {
    switch (ruleType) {
      case DateRuleType.daily:
        return '每日';
      case DateRuleType.workday:
        return '工作日（周一至周五）';
      case DateRuleType.holiday:
        return '节假日（周六、周日）';
      case DateRuleType.weeklyInterval:
        final sorted = [...weekdays]..sort();
        final names = sorted.map(weekdayName).join('、');
        return weekInterval == 1 ? '每周 $names' : '每隔 $weekInterval 周的 $names';
      case DateRuleType.monthlyDay:
        final sorted = [...monthDays]..sort();
        return '每月 ${sorted.map((e) => '$e 号').join('、')}';
    }
  }

  /// 星期数字转中文
  static String weekdayName(int w) {
    const names = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (w < 1 || w > 7) return '';
    return names[w];
  }

  /// 转为数据库记录（SQLite 不支持 bool / List，需转换）
  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'enabled': enabled ? 1 : 0,
        'ruleType': ruleType.name,
        'weekInterval': weekInterval,
        'weekdays': jsonEncode(weekdays),
        'anchorDate': anchorDate.millisecondsSinceEpoch,
        'monthDays': jsonEncode(monthDays),
        'monthDayFallback': monthDayFallback.name,
        'snoozeMinutes': snoozeMinutes,
        'maxSnoozeTimes': maxSnoozeTimes,
        'vibrate': vibrate ? 1 : 0,
        'ringDurationSeconds': ringDurationSeconds,
      };

  /// 从数据库记录还原
  factory Alarm.fromMap(Map<String, dynamic> m) => Alarm(
        id: m['id'] as String,
        label: (m['label'] ?? '') as String,
        hour: m['hour'] as int,
        minute: m['minute'] as int,
        enabled: (m['enabled'] as int) == 1,
        ruleType: DateRuleType.fromName(m['ruleType'] as String),
        weekInterval: m['weekInterval'] as int,
        weekdays:
            (jsonDecode(m['weekdays'] as String) as List).map((e) => e as int).toList(),
        anchorDate:
            DateTime.fromMillisecondsSinceEpoch(m['anchorDate'] as int),
        monthDays:
            (jsonDecode(m['monthDays'] as String) as List).map((e) => e as int).toList(),
        monthDayFallback: MonthDayFallback.fromName(m['monthDayFallback'] as String),
        snoozeMinutes: m['snoozeMinutes'] as int,
        maxSnoozeTimes: m['maxSnoozeTimes'] as int,
        vibrate: (m['vibrate'] as int) == 1,
        ringDurationSeconds: m['ringDurationSeconds'] as int,
      );

  /// 传给 Android 原生侧的完整描述。
  /// 原生侧会把它持久化，并在每次响铃结束后自己算下一次（不依赖 Flutter 进程存活）。
  Map<String, dynamic> toNativeMap() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'enabled': enabled,
        'ruleType': ruleType.name,
        'weekInterval': weekInterval,
        'weekdays': weekdays,
        'anchorDateMillis': anchorDate.millisecondsSinceEpoch,
        'monthDays': monthDays,
        'monthDayFallback': monthDayFallback.name,
        'snoozeMinutes': snoozeMinutes,
        'maxSnoozeTimes': maxSnoozeTimes,
        'vibrate': vibrate,
        'ringDurationSeconds': ringDurationSeconds,
      };

  Alarm copyWith({
    String? label,
    int? hour,
    int? minute,
    bool? enabled,
    DateRuleType? ruleType,
    int? weekInterval,
    List<int>? weekdays,
    DateTime? anchorDate,
    List<int>? monthDays,
    MonthDayFallback? monthDayFallback,
    int? snoozeMinutes,
    int? maxSnoozeTimes,
    bool? vibrate,
    int? ringDurationSeconds,
  }) =>
      Alarm(
        id: id,
        label: label ?? this.label,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        enabled: enabled ?? this.enabled,
        ruleType: ruleType ?? this.ruleType,
        weekInterval: weekInterval ?? this.weekInterval,
        weekdays: weekdays ?? this.weekdays,
        anchorDate: anchorDate ?? this.anchorDate,
        monthDays: monthDays ?? this.monthDays,
        monthDayFallback: monthDayFallback ?? this.monthDayFallback,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        maxSnoozeTimes: maxSnoozeTimes ?? this.maxSnoozeTimes,
        vibrate: vibrate ?? this.vibrate,
        ringDurationSeconds: ringDurationSeconds ?? this.ringDurationSeconds,
      );
}
