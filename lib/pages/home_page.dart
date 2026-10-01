import 'package:flutter/material.dart';

import '../core/alarm_store.dart';
import '../models/alarm.dart';
import '../platform/alarm_platform.dart';
import '../widgets/alarm_tile.dart';
import 'edit_alarm_page.dart';
import 'settings_page.dart';

/// ============================================================
/// 页面 1 · 首页（闹钟列表）
///
/// 元素与跳转：
///   · 右上角齿轮   → 设置页
///   · 闹钟卡片点击  → 编辑闹钟页
///   · 卡片开关      → 即时启用/停用并重排
///   · 卡片左滑      → 删除（二次确认）
///   · 右下角 +      → 编辑闹钟页（新建）
///   · 顶部告警条    → 权限缺失时提示，点击去设置页
/// ============================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 是否缺少关键权限（精确闹钟 / 电池优化豁免）
  bool _hasPermissionIssue = false;

  /// 后台守护是否被关掉了（关掉后小米清理后台容易丢闹钟）
  bool _keepAliveOff = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  /// 启动时自检一次，缺权限就顶一条告警条
  Future<void> _checkPermissions() async {
    final exact = await AlarmPlatform.canScheduleExact();
    final battery = await AlarmPlatform.isBatteryOptimizationIgnored();
    final keepAlive = await AlarmPlatform.isKeepAliveEnabled();
    if (!mounted) return;
    setState(() {
      _hasPermissionIssue = !exact || !battery;
      _keepAliveOff = !keepAlive;
    });
  }

  /// 是否有任何需要提醒用户的可靠性问题
  bool get _hasWarning => _hasPermissionIssue || _keepAliveOff;

  @override
  Widget build(BuildContext context) {
    final store = AlarmStore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('智闹'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              _checkPermissions();
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          if (store.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              if (_hasWarning) _permissionBanner(context),
              Expanded(
                child: store.alarms.isEmpty
                    ? _emptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 96),
                        itemCount: store.alarms.length,
                        itemBuilder: (context, index) {
                          final alarm = store.alarms[index];
                          return AlarmTile(
                            alarm: alarm,
                            onTap: () => _openEditor(alarm),
                            onToggle: (v) => store.toggle(alarm, v),
                            onDelete: () => store.remove(alarm.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('新建闹钟'),
      ),
    );
  }

  /// 打开编辑页；传入 null 表示新建
  Future<void> _openEditor(Alarm? alarm) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditAlarmPage(alarm: alarm)),
    );
  }

  /// 权限告警条：小米手机上这是闹钟能不能响的分水岭
  Widget _permissionBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 权限缺失是"可能不响"，后台守护关掉是"更容易丢"，两种文案分开说
    final text = _hasPermissionIssue
        ? '可靠性检查未通过，闹钟可能不响。请完成设置。'
        : '后台守护已关闭，从最近任务划掉智闹可能丢闹钟。';

    return MaterialBanner(
      backgroundColor: scheme.errorContainer,
      leading: Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
      content: Text(
        text,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
            _checkPermissions();
          },
          child: const Text('去设置'),
        ),
      ],
    );
  }

  /// 空列表引导
  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.alarm_add, size: 72, color: scheme.outlineVariant),
            const SizedBox(height: 20),
            Text(
              '还没有闹钟',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '「日期规则 + 目标时间」两个条件同时满足才响。\n'
              '试试周期二周的周三，或者每月 1 号。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.6,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
