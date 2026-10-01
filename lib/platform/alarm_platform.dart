import 'package:flutter/services.dart';

import '../models/alarm.dart';

/// ============================================================
/// Flutter ↔ Android 原生 的唯一通道
///
/// 为什么闹钟排程要交给原生？
///   Dart 的 Timer 在 App 进入后台后被系统冻结，闹钟必不响。
///   必须用 Android 原生的 AlarmManager.setAlarmClock()，
///   它在小米手机上享有系统级白名单豁免，最不容易被省电策略杀掉。
///
/// 分工：
///   Dart  → 负责 UI、增删改、把整份闹钟列表同步给原生
///   原生  → 负责实际排程、响铃、响完之后自己算下一次
/// ============================================================
class AlarmPlatform {
  AlarmPlatform._();

  static const MethodChannel _channel =
      MethodChannel('com.zhinao.alarm/control');

  /// 原生侧收到响铃事件后会回调这里（用于刷新列表上的"下次响铃"）
  static const EventChannel _events =
      EventChannel('com.zhinao.alarm/events');

  /// 全量同步：把当前所有闹钟交给原生，原生据此重新排程。
  /// 任何增删改后都应调用一次，保证原生与 Dart 状态一致。
  static Future<void> syncAll(List<Alarm> alarms) async {
    try {
      await _channel.invokeMethod('syncAll', {
        'alarms': alarms.map((a) => a.toNativeMap()).toList(),
      });
    } on PlatformException catch (e) {
      // 同步失败不阻塞界面，但要能定位问题
      // ignore: avoid_print
      print('[智闹] syncAll 失败: ${e.message}');
    }
  }

  /// 取消单个闹钟的排程
  static Future<void> cancel(String id) async {
    try {
      await _channel.invokeMethod('cancel', {'id': id});
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[智闹] cancel 失败: ${e.message}');
    }
  }

  /// 取消全部排程
  static Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod('cancelAll');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[智闹] cancelAll 失败: ${e.message}');
    }
  }

  /// ------------------------------------------------------------
  /// 可靠性检查：下面几项任何一项不满足，闹钟都可能不响
  /// ------------------------------------------------------------

  /// 原生算出的「下次响铃」文案，如「明天 07:30」；没有启用的闹钟时返回「暂无启用的闹钟」。
  static Future<String> nextTriggerText() async {
    try {
      final r = await _channel.invokeMethod<String>('nextTriggerText');
      return r ?? '暂无启用的闹钟';
    } on PlatformException {
      return '暂无启用的闹钟';
    }
  }

  /// 立即全量重排一次闹钟（设置页的「立即修复」按钮）
  static Future<void> rescheduleAll() async {
    try {
      await _channel.invokeMethod('rescheduleAll');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[智闹] rescheduleAll 失败: ${e.message}');
    }
  }

  /// 是否开启了「后台守护」（常驻通知，防止被小米清理掉闹钟排程）。默认开启。
  static Future<bool> isKeepAliveEnabled() async {
    try {
      final r = await _channel.invokeMethod<bool>('isKeepAliveEnabled');
      return r ?? true;
    } on PlatformException {
      return true;
    }
  }

  /// 开启 / 关闭「后台守护」
  static Future<void> setKeepAlive(bool enabled) =>
      _channel.invokeMethod('setKeepAlive', {'enabled': enabled});

  /// 是否已获得「精确闹钟」权限（Android 12+ 需手动授予）
  static Future<bool> canScheduleExact() async {
    try {
      final r = await _channel.invokeMethod<bool>('canScheduleExact');
      return r ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 跳转到系统的「闹钟和提醒」授权页
  static Future<void> requestExactPermission() =>
      _channel.invokeMethod('requestExactPermission');

  /// 是否已豁免电池优化（小米必开）
  static Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final r = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return r ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 弹出「是否允许后台运行」的系统对话框
  static Future<void> requestIgnoreBatteryOptimization() =>
      _channel.invokeMethod('requestIgnoreBatteryOptimizations');

  /// 跳转到小米的「自启动管理」页
  static Future<void> openAutoStartSettings() =>
      _channel.invokeMethod('openAutoStartSettings');

  /// 跳转到本 App 的通知设置页
  static Future<void> openNotificationSettings() =>
      _channel.invokeMethod('openNotificationSettings');

  /// 跳转到本 App 的应用详情页（兜底入口）
  static Future<void> openAppSettings() =>
      _channel.invokeMethod('openAppSettings');

  /// 原生响铃事件的广播流（响铃开始/结束/贪睡时推送），
  /// 界面收到后刷新"下次响铃"显示。
  static Stream<dynamic> get ringEvents => _events.receiveBroadcastStream();
}
