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
/// 6 种规则互斥单选：
///   每日 / 每隔 N 天 / 工作日 / 节假日 / 每隔 N 周的周几 / 每月 N 号
/// 后三种选中后会就地展开二级参数，不需要再跳一层页面。
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
  late int _dayInterval = widget.alarm.effectiveDayInterval;
  late DateTime _dayAnchor = widget.alarm.dayAnchorDate;
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

                  // ---- 每隔 N 天 ----
                  _ruleOption(
                    DateRuleType.intervalDays,
                    '每隔几天',
                    Icons.timelapse_outlined,
                    subtitle: _intervalSummary(),
                  ),
                  if (_ruleType == DateRuleType.intervalDays)
                    _intervalPanel(context),

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
  // 二级面板 · 每隔 N 天
  // ============================================================
  Widget _intervalPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // 常用间隔，点一下就选中，省得一直按加号
    const presets = <int>[2, 3, 4, 5, 6, 7, 10, 14, 15, 21, 30];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- 间隔天数：步进器 ----------
          Text('间隔天数', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                onPressed: _dayInterval > 2
                    ? () => setState(() => _dayInterval--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: '减少一天',
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '每隔 $_dayInterval 天',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: _dayInterval < 99
                    ? () => setState(() => _dayInterval++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: '增加一天',
              ),
            ],
          ),

          // ---------- 常用间隔快捷选择 ----------
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((n) {
              return ChoiceChip(
                label: Text('$n 天'),
                selected: _dayInterval == n,
                onSelected: (_) => setState(() => _dayInterval = n),
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // ---------- 起始日期 ----------
          Text('从哪天开始算', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickAnchorDate,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.event, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(_dayAnchorText(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      )),
                  const Spacer(),
                  Text('修改',
                      style: TextStyle(color: scheme.primary, fontSize: 12)),
                ],
              ),
            ),
          ),

          // ---------- 快捷：今天 / 明天 ----------
          const SizedBox(height: 2),
          Row(
            children: [
              TextButton(
                onPressed: () => _setAnchorTo(DateTime.now()),
                child: const Text('今天'),
              ),
              TextButton(
                onPressed: () =>
                    _setAnchorTo(DateTime.now().add(const Duration(days: 1))),
                child: const Text('明天'),
              ),
            ],
          ),

          // ---------- 人话解释，避免用户困惑"从哪天算" ----------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: scheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '起始日当天算第 1 次，之后每隔 $_dayInterval 天响一次。'
                  '想每天都响请直接用上面的「每天都响」。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
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

  String _intervalSummary() => '每隔 $_dayInterval 天';

  /// 起始日期的中文展示，如 "2026年9月29日 周二"
  String _dayAnchorText() {
    const weekdayChars = '一二三四五六日';
    final w = weekdayChars[_dayAnchor.weekday - 1];
    return '${_dayAnchor.year}年${_dayAnchor.month}月${_dayAnchor.day}日 周$w';
  }

  /// 把起始日设为某一天（只取年月日）
  void _setAnchorTo(DateTime d) =>
      setState(() => _dayAnchor = DateTime(d.year, d.month, d.day));

  /// 打开系统日期选择器修改起始日
  Future<void> _pickAnchorDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dayAnchor,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3, 12, 31),
      helpText: '选择起始日期',
    );
    if (picked != null) _setAnchorTo(picked);
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
      dayInterval: _dayInterval,
      // 只有「每隔 N 天」才更新锚点，避免改别的规则时误改周差锚点
      anchorDate: _ruleType == DateRuleType.intervalDays
          ? _dayAnchor
          : widget.alarm.anchorDate,
      weekdays: _weekdays.toList()..sort(),
      monthDays: _monthDays.toList()..sort(),
      monthDayFallback: _fallback,
    );
    Navigator.of(context).pop(updated);
  }
}
