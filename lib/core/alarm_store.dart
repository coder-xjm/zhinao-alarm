import 'package:flutter/foundation.dart';

import '../models/alarm.dart';
import '../platform/alarm_platform.dart';
import 'alarm_repository.dart';
import 'date_rule_engine.dart';

/// ============================================================
/// 全局状态：闹钟列表 + 增删改
///
/// 刻意不引入 Provider / Riverpod 等第三方状态管理，
/// 用 Flutter 自带的 ChangeNotifier + AnimatedBuilder，依赖更少、更不容易出错。
///
/// 每次数据变动都会：
///   1. 写入 SQLite（本地持久化）
///   2. 调用 syncAll 让原生侧重新排程
///   3. notifyListeners() 刷新界面
/// ============================================================
class AlarmStore extends ChangeNotifier {
  AlarmStore._();

  static final AlarmStore instance = AlarmStore._();

  List<Alarm> _alarms = [];
  bool _loading = true;

  /// 全部闹钟（只读）
  List<Alarm> get alarms => List.unmodifiable(_alarms);

  /// 是否正在从数据库加载
  bool get loading => _loading;

  /// App 启动时调用
  Future<void> init() async {
    _alarms = await AlarmRepository.instance.loadAll();
    _sort();
    _loading = false;
    notifyListeners();
    await _syncToNative();
  }

  /// 新增或更新一个闹钟
  Future<void> save(Alarm alarm) async {
    await AlarmRepository.instance.upsert(alarm);

    final index = _alarms.indexWhere((e) => e.id == alarm.id);
    if (index >= 0) {
      _alarms[index] = alarm;
    } else {
      _alarms.add(alarm);
    }

    _sort();
    notifyListeners();
    await _syncToNative();
  }

  /// 删除一个闹钟
  Future<void> remove(String id) async {
    await AlarmRepository.instance.delete(id);
    _alarms.removeWhere((e) => e.id == id);
    notifyListeners();
    await _syncToNative();
  }

  /// 切换启用状态
  Future<void> toggle(Alarm alarm, bool enabled) async {
    await save(alarm.copyWith(enabled: enabled));
  }

  /// 计算某个闹钟的下一次响铃时刻（未启用返回 null）
  DateTime? nextTriggerOf(Alarm alarm) =>
      alarm.enabled ? DateRuleEngine.nextTrigger(alarm, DateTime.now()) : null;

  /// 下一次响铃的文案，如 "明天 07:00"
  String nextTriggerText(Alarm alarm) {
    if (!alarm.enabled) return '已停用';
    return DateRuleEngine.describeNext(nextTriggerOf(alarm));
  }

  /// 把所有闹钟交给原生侧重新排程
  Future<void> _syncToNative() => AlarmPlatform.syncAll(_alarms);

  /// 供外部（如从原生响铃返回后）强制刷新
  Future<void> refresh() async {
    _alarms = await AlarmRepository.instance.loadAll();
    _sort();
    notifyListeners();
  }

  /// 按时间升序排列
  void _sort() =>
      _alarms.sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
}
