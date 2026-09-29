import 'package:flutter/material.dart';

import '../core/alarm_store.dart';
import '../models/alarm.dart';

/// ============================================================
/// 首页的单个闹钟卡片
///
/// 展示三行信息：
///   第 1 行：目标时间（大号）+ 开关
///   第 2 行：标签
///   第 3 行：条件一摘要 + 下次响铃时间
/// ============================================================
class AlarmTile extends StatelessWidget {
  const AlarmTile({
    super.key,
    required this.alarm,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final Alarm alarm;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 停用的闹钟整体降低存在感
    final opacity = alarm.enabled ? 1.0 : 0.45;

    return Dismissible(
      key: ValueKey(alarm.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 0,
        color: scheme.surfaceContainerHighest.withOpacity( 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Opacity(
              opacity: opacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---------- 第 1 行：时间 + 开关 ----------
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        alarm.timeText,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: alarm.enabled,
                        onChanged: onToggle,
                      ),
                    ],
                  ),

                  // ---------- 第 2 行：标签 ----------
                  if (alarm.label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        alarm.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // ---------- 第 3 行：条件一 + 下次响铃 ----------
                  Row(
                    children: [
                      Icon(Icons.event_repeat,
                          size: 15, color: scheme.outline),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          alarm.ruleSummary,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        alarm.enabled
                            ? Icons.alarm_on
                            : Icons.alarm_off,
                        size: 15,
                        color: alarm.enabled ? scheme.primary : scheme.outline,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        alarm.enabled
                            ? '下次 ${AlarmStore.instance.nextTriggerText(alarm)}'
                            : '已停用',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: alarm.enabled
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 删除前二次确认，避免误触
  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除闹钟'),
        content: Text('确定删除 ${alarm.timeText}'
            '${alarm.label.isEmpty ? '' : ' · ${alarm.label}'} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
