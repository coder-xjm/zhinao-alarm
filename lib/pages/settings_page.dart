import 'package:flutter/material.dart';

import '../platform/alarm_platform.dart';

/// ============================================================
/// 页面 5 · 设置页 · 可靠性检查
///
/// 为什么这一页很重要：
///   小米手机对第三方 App 的后台限制很严。下面任意一项没开，
///   闹钟都可能"该响的时候不响"。所以把检查项集中在这里，
///   并全部提供一键跳转到对应的系统设置页。
///
/// v1.2.0 新增「后台守护」：
///   常驻一条通知显示下次响铃时间，让 App 在系统眼里始终处于
///   "正在运行"状态。用户从最近任务里划掉 App 时，小米就不会把它
///   判定为强行停止（强行停止会撤销所有闹钟，且不会自己恢复）。
/// ============================================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _exactAlarm; // 精确闹钟权限
  bool? _battery; // 电池优化豁免
  bool _keepAlive = true; // 后台守护开关
  String _nextText = '读取中…'; // 下次响铃文案

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// 重新读取系统状态（从系统设置返回后要刷新）
  Future<void> _refresh() async {
    final exact = await AlarmPlatform.canScheduleExact();
    final battery = await AlarmPlatform.isBatteryOptimizationIgnored();
    final keepAlive = await AlarmPlatform.isKeepAliveEnabled();
    final next = await AlarmPlatform.nextTriggerText();
    if (!mounted) return;
    setState(() {
      _exactAlarm = exact;
      _battery = battery;
      _keepAlive = keepAlive;
      _nextText = next;
    });
  }

  /// 切换后台守护
  Future<void> _toggleKeepAlive(bool value) async {
    setState(() => _keepAlive = value);
    await AlarmPlatform.setKeepAlive(value);
    await AlarmPlatform.rescheduleAll();
    await _refresh();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '后台守护已开启：通知栏会常驻一条「下次响铃」提示'
              : '后台守护已关闭：通知栏干净了，但小米清理后台后闹钟更容易丢',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
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

          // ---------- v1.2.0 后台守护 ----------
          _sectionTitle(context, '后台守护'),
          SwitchListTile(
            secondary: Icon(
              Icons.shield_moon_outlined,
              color: _keepAlive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: const Text('后台守护（推荐开启）'),
            subtitle: const Text(
              '通知栏常驻一条「下次响铃」提示。开着它，从最近任务里划掉智闹也不会丢闹钟；'
              '关掉后通知栏更干净，但小米清理后台后闹钟更容易失效。',
              style: TextStyle(fontSize: 12),
            ),
            value: _keepAlive,
            onChanged: _toggleKeepAlive,
          ),
          ListTile(
            leading: Icon(
              Icons.schedule,
              color: theme.colorScheme.primary,
            ),
            title: const Text('下次响铃'),
            subtitle: Text(
              _nextText,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: IconButton(
              tooltip: '立即重排闹钟',
              icon: const Icon(Icons.build_outlined),
              onPressed: () async {
                await AlarmPlatform.rescheduleAll();
                await _refresh();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已按当前闹钟重新排程')),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // ---------- 厂商专属设置 ----------
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
            subtitle: '必须允许通知，否则后台守护无法常驻',
            onTap: AlarmPlatform.openNotificationSettings,
          ),
          _actionTile(
            context,
            icon: Icons.settings_applications_outlined,
            title: '应用详情页',
            subtitle: '去「省电策略」里把智闹选成「无限制」',
            onTap: AlarmPlatform.openAppSettings,
          ),

          const SizedBox(height: 16),

          // ---------- 说明 ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer.withOpacity(0.5),
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
                      Text('为什么关了 App 闹钟就不响',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '小米（MIUI / HyperOS）对后台管得很严。从最近任务里划掉一个没白名单的 App，'
                    '会被它当成「强行停止」——系统会撤销这个 App 注册过的所有闹钟，'
                    '并且之后连开机广播都不再发给它，直到你下次手动打开它。\n\n'
                    '所以本 App 用了三层保险：\n'
                    '① 响铃瞬间立刻排下一次，不依赖界面存活；\n'
                    '② 后台守护常驻通知，划掉任务时立刻全量重排；\n'
                    '③ 每 15 分钟自检一次，发现排程丢了就补上。\n\n'
                    '唯一防不住的是「强行停止」和「一键清理」——那两种情况下系统会连'
                    '自检机制一起撤销。请把上面三项小米设置都打开，并建议在最近任务里'
                    '把智闹下拉锁定，就万无一失了。',
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
              '智闹 v1.2.0',
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
        color: color.withOpacity(0.12),
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
                  allGood
                      ? (_keepAlive ? '闹钟可以正常响铃' : '建议开启后台守护，抗小米清理')
                      : '闹钟可能不响，请逐项开启',
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
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
