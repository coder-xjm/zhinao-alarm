import 'package:flutter/material.dart';

import '../platform/alarm_platform.dart';

/// ============================================================
/// 页面 5 · 设置页 · 可靠性检查
///
/// 为什么这一页很重要：
///   小米手机对第三方 App 的后台限制很严。下面任意一项没开，
///   闹钟都可能"该响的时候不响"。所以把检查项集中在这里，
///   并全部提供一键跳转到对应的系统设置页。
/// ============================================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _exactAlarm; // 精确闹钟权限
  bool? _battery; // 电池优化豁免

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// 重新读取系统状态（从系统设置返回后要刷新）
  Future<void> _refresh() async {
    final exact = await AlarmPlatform.canScheduleExact();
    final battery = await AlarmPlatform.isBatteryOptimizationIgnored();
    if (!mounted) return;
    setState(() {
      _exactAlarm = exact;
      _battery = battery;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allGood = _exactAlarm == true && _battery == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            tooltip: '重新检查',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---------- 总体状态 ----------
          _statusHeader(context, allGood),

          const SizedBox(height: 8),

          _sectionTitle(context, '可靠性检查'),
          _checkTile(
            context,
            icon: Icons.alarm,
            title: '精确闹钟权限',
            subtitle: '允许 App 在精确到分钟的时间点唤醒',
            state: _exactAlarm,
            onTap: () async {
              await AlarmPlatform.requestExactPermission();
              await Future<void>.delayed(const Duration(seconds: 1));
              await _refresh();
            },
          ),
          _checkTile(
            context,
            icon: Icons.battery_charging_full,
            title: '电池优化豁免',
            subtitle: '小米必开。不开会被省电策略冻结，闹钟不响',
            state: _battery,
            onTap: () async {
              await AlarmPlatform.requestIgnoreBatteryOptimization();
              await Future<void>.delayed(const Duration(seconds: 1));
              await _refresh();
            },
          ),

          const SizedBox(height: 8),

          _sectionTitle(context, '小米专属设置'),
          _actionTile(
            context,
            icon: Icons.play_circle_outline,
            title: '自启动管理',
            subtitle: '必须允许。否则重启手机后闹钟不会重新排程',
            onTap: AlarmPlatform.openAutoStartSettings,
          ),
          _actionTile(
            context,
            icon: Icons.notifications_outlined,
            title: '通知设置',
            subtitle: '建议允许横幅通知，方便响铃时快速操作',
            onTap: AlarmPlatform.openNotificationSettings,
          ),
          _actionTile(
            context,
            icon: Icons.settings_applications_outlined,
            title: '应用详情页',
            subtitle: '找不到上面两项时，在这里手动设置',
            onTap: AlarmPlatform.openAppSettings,
          ),

          const SizedBox(height: 16),

          // ---------- 说明 ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 18, color: theme.colorScheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Text('为什么需要这些设置',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '安卓为省电会限制后台应用，小米的限制尤其严格。'
                    '闹钟类 App 必须获得上面这些豁免，才能在息屏、'
                    '清理后台、甚至重启之后依然准时响铃。\n\n'
                    '本 App 的响铃使用系统级闹钟通道（AlarmManager.setAlarmClock），'
                    '这是安卓上优先级最高、最不容易被拦截的方式，'
                    '但仍需你手动放行自启动与省电限制。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              '智闹 v1.0.0',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 顶部总体状态
  // ============================================================
  Widget _statusHeader(BuildContext context, bool allGood) {
    final scheme = Theme.of(context).colorScheme;
    final color = allGood ? scheme.primary : scheme.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            allGood ? Icons.verified_rounded : Icons.error_outline,
            color: color,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allGood ? '可靠性检查通过' : '还有设置没完成',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allGood ? '闹钟可以正常响铃' : '闹钟可能不响，请逐项开启',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );

  /// 可读状态 + 可跳转的检查项
  Widget _checkTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool? state,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final ok = state == true;
    final iconColor = ok ? scheme.primary : scheme.error;

    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title),
      subtitle: Text(subtitle,
          style: TextStyle(
            fontSize: 12,
            color: ok ? scheme.onSurfaceVariant : scheme.error,
          )),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            color: iconColor,
            size: 20,
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }

  /// 无状态可读、纯跳转项
  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
