import 'package:flutter/material.dart';

import '../models/alarm.dart';

/// 打开「条件一 · 哪天响」底部弹层。
/// 返回修改后的 Alarm；用户取消则返回 null。
Future<Alarm?> showRulePicker(BuildContext context, Alarm alarm) {
  return showModalBottomSheet<Alarm>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RulePickerSheet(alarm: alarm),
  );
}

/// ============================================================
/// 条件一配置弹层
///
/// 5 种规则互斥单选：
///   每日 / 工作日 / 节假日 / 每隔 N 周的周几 / 每月 N 号
/// 后两种选中后会就地展开二级参数，不需要再跳一层页面。
/// ============================================================
class _RulePickerSheet extends StatefulWidget {
  const _RulePickerSheet({required this.alarm});

  final Alarm alarm;

  @override
  State<_RulePickerSheet> createState() => _RulePickerSheetState();
}

class _RulePickerSheetState extends State<_RulePickerSheet> {
  late DateRuleType _ruleType = widget.alarm.ruleType;
  late int _weekInterval = widget.alarm.weekInterval;
  late Set<int> _weekdays = {...widget.alarm.weekdays};
  late Set<int> _monthDays = {...widget.alarm.monthDays};
  late MonthDayFallback _fallback = widget.alarm.monthDayFallback;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---------- 标题 ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(
              children: [
                Text('条件一 · 哪天响',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          const Divider(height: 1),

          // ---------- 主体 ----------
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  _ruleOption(DateRuleType.daily, '每天都响', Icons.wb_sunny_outlined),
                  _ruleOption(DateRuleType.workday, '工作日', Icons.work_outline,
                      subtitle: '周一至周五'),
                  _ruleOption(DateRuleType.holiday, '节假日', Icons.weekend_outlined,
                      subtitle: '周六、周日'),

                  // ---- 每隔 N 周的周几 ----
                  _ruleOption(
                    DateRuleType.weeklyInterval,
                    '每隔几周的周几',
                    Icons.event_repeat_outlined,
                    subtitle: _weeklySummary(),
                  ),
                  if (_ruleType == DateRuleType.weeklyInterval)
                    _weeklyPanel(context),

                  // ---- 每月 N 号 ----
                  _ruleOption(
                    DateRuleType.monthlyDay,
                    '每月几号',
                    Icons.calendar_month_outlined,
                    subtitle: _monthlySummary(),
                  ),
                  if (_ruleType == DateRuleType.monthlyDay)
                    _monthlyPanel(context),
                ],
              ),
            ),
          ),

          // ---------- 底部完成按钮 ----------
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canConfirm ? _confirm : null,
                child: const Text('完成'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 单项规则
  // ============================================================
  Widget _ruleOption(DateRuleType type, String title, IconData icon,
      {String? subtitle}) {
    final selected = _ruleType == type;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: () => setState(() => _ruleType = type),
      leading: Icon(icon,
          color: selected ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontSize: 12,
              )),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? scheme.primary : scheme.outline,
      ),
    );
  }

  /// 单选样式的小行（用于「小月怎么处理」）
  Widget _radioRow(String title, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? scheme.primary : scheme.outline,
      ),
    );
  }

  // ============================================================
  // 二级面板 · 每隔 N 周的周几
  // ============================================================
  Widget _weeklyPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity( 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- 间隔选择 ----
          Text('间隔', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (i) => i + 1).map((n) {
              return ChoiceChip(
                label: Text(n == 1 ? '每周' : '隔 $n 周'),
                selected: _weekInterval == n,
                onSelected: (_) => setState(() => _weekInterval = n),
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // ---- 周几多选 ----
          Text('周几（可多选）', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (i) => i + 1).map((w) {
              final selected = _weekdays.contains(w);
              return FilterChip(
                label: Text(Alarm.weekdayName(w).substring(1)),
                selected: selected,
                showCheckmark: false,
                onSelected: (v) => setState(() {
                  if (v) {
                    _weekdays.add(w);
                  } else {
                    _weekdays.remove(w);
                  }
                }),
              );
            }).toList(),
          ),

          // ---- 锚点说明，避免用户困惑"隔 2 周从哪周算" ----
          if (_weekInterval > 1) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: scheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '以创建当周（${_anchorText()}）为第 1 周计算',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // 二级面板 · 每月几号
  // ============================================================
  Widget _monthlyPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity( 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('日期（可多选）', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),

          // 1~31 号选择网格
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: List.generate(31, (i) => i + 1).map((d) {
              final selected = _monthDays.contains(d);
              return SizedBox(
                width: 44,
                height: 38,
                child: FilterChip(
                  label: Text('$d'),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _monthDays.add(d);
                    } else {
                      _monthDays.remove(d);
                    }
                  }),
                  labelPadding: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // 小月兜底策略：只在选了 29/30/31 时才需要
          if (_monthDays.any((d) => d > 28)) ...[
            Text('小月没有这一天时',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            _radioRow('跳过本月', _fallback == MonthDayFallback.skip,
                () => setState(() => _fallback = MonthDayFallback.skip)),
            _radioRow('顺延到当月最后一天', _fallback == MonthDayFallback.lastDay,
                () => setState(() => _fallback = MonthDayFallback.lastDay)),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // 辅助
  // ============================================================

  /// 完成按钮是否可用：选了参数就必须至少选一个
  bool get _canConfirm {
    switch (_ruleType) {
      case DateRuleType.weeklyInterval:
        return _weekdays.isNotEmpty;
      case DateRuleType.monthlyDay:
        return _monthDays.isNotEmpty;
      default:
        return true;
    }
  }

  String _weeklySummary() {
    if (_weekdays.isEmpty) return '还没选周几';
    final sorted = _weekdays.toList()..sort();
    final names = sorted.map(Alarm.weekdayName).join('、');
    return _weekInterval == 1 ? '每周 $names' : '每隔 $_weekInterval 周的 $names';
  }

  String _monthlySummary() {
    if (_monthDays.isEmpty) return '还没选日期';
    final sorted = _monthDays.toList()..sort();
    return '每月 ${sorted.map((e) => '$e 号').join('、')}';
  }

  String _anchorText() {
    final a = widget.alarm.anchorDate;
    return '${a.month}月${a.day}日 周${'一二三四五六日'[a.weekday - 1]}';
  }

  /// 回传结果
  void _confirm() {
    final updated = widget.alarm.copyWith(
      ruleType: _ruleType,
      weekInterval: _weekInterval,
      weekdays: _weekdays.toList()..sort(),
      monthDays: _monthDays.toList()..sort(),
      monthDayFallback: _fallback,
    );
    Navigator.of(context).pop(updated);
  }
}
