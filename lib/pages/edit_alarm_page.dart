import 'package:flutter/material.dart';

import '../core/alarm_store.dart';
import '../core/date_rule_engine.dart';
import '../models/alarm.dart';
import '../widgets/rule_picker_sheet.dart';

/// ============================================================
/// 页面 2 · 编辑闹钟页
///
/// 这一页同时承载两个条件的设置：
///   条件二（目标时间）→ 顶部大滚轮
///   条件一（日期规则）→ 中间的「日期规则」行，点击弹出 rule_picker_sheet
///
/// 底部实时显示「未来 3 次响铃」，让用户立刻看到两个条件组合后的真实结果。
/// ============================================================
class EditAlarmPage extends StatefulWidget {
  const EditAlarmPage({super.key, this.alarm});

  /// 传入 null 表示新建
  final Alarm? alarm;

  @override
  State<EditAlarmPage> createState() => _EditAlarmPageState();
}

class _EditAlarmPageState extends State<EditAlarmPage> {
  late Alarm _alarm;
  late final TextEditingController _labelCtrl;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  bool get _isNew => widget.alarm == null;

  @override
  void initState() {
    super.initState();
    _alarm = widget.alarm ?? Alarm();
    _labelCtrl = TextEditingController(text: _alarm.label);
    _hourCtrl = FixedExtentScrollController(initialItem: _alarm.hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: _alarm.minute);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  /// 当前编辑中的草稿（用于实时算预览）
  Alarm get _draft => _alarm.copyWith(label: _labelCtrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建闹钟' : '编辑闹钟'),
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        leadingWidth: 72,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _timeWheelCard(context),
          const SizedBox(height: 8),
          _labelCard(context),
          const SizedBox(height: 8),
          _settingsCard(context),
          const SizedBox(height: 8),
          _previewCard(context),
          if (!_isNew) ...[
            const SizedBox(height: 24),
            _deleteButton(context),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 条件二：目标时间滚轮
  // ============================================================
  Widget _timeWheelCard(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity( 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            '条件二 · 目标时间',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 168,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ---- 小时 ----
                _wheel(
                  controller: _hourCtrl,
                  count: 24,
                  currentValue: _alarm.hour,
                  onChanged: (v) =>
                      setState(() => _alarm = _alarm.copyWith(hour: v)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    ':',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w300,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // ---- 分钟 ----
                _wheel(
                  controller: _minuteCtrl,
                  count: 60,
                  currentValue: _alarm.minute,
                  onChanged: (v) =>
                      setState(() => _alarm = _alarm.copyWith(minute: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 单个数字滚轮
  ///
  /// 注意：这里用 currentValue 判断选中项，而不是 controller.selectedItem ——
  /// 后者在首帧（controller 尚未 attach 到滚动视图）时会触发断言失败。
  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required int currentValue,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 92,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 56,
        perspective: 0.004,
        diameterRatio: 1.8,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, index) {
            final selected = index == currentValue;
            return Center(
              child: Text(
                index.toString().padLeft(2, '0'),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w400 : FontWeight.w300,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant.withOpacity( 0.35),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // 标签
  // ============================================================
  Widget _labelCard(BuildContext context) {
    return _card(
      context,
      children: [
        ListTile(
          leading: const Icon(Icons.label_outline),
          title: TextField(
            controller: _labelCtrl,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '标签（可选），如 早起 / 交房租',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 条件一入口 + 响铃行为
  // ============================================================
  Widget _settingsCard(BuildContext context) {
    final theme = Theme.of(context);

    return _card(
      context,
      children: [
        // ---- 条件一：点击弹出规则选择 ----
        ListTile(
          leading: Icon(Icons.event_repeat, color: theme.colorScheme.primary),
          title: const Text('条件一 · 哪天响'),
          subtitle: Text(
            _alarm.ruleSummary,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickRule,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),

        // ---- 响铃时长 ----
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('响铃时长'),
          subtitle: Text('${_alarm.ringDurationSeconds ~/ 60} 分钟后自动停'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickRingDuration(context),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),

        // ---- 贪睡 ----
        ListTile(
          leading: const Icon(Icons.snooze_outlined),
          title: const Text('贪睡'),
          subtitle: Text(
              '${_alarm.snoozeMinutes} 分钟后重响，最多 ${_alarm.maxSnoozeTimes} 次'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickSnooze(context),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),

        // ---- 震动 ----
        SwitchListTile(
          secondary: const Icon(Icons.vibration),
          title: const Text('震动'),
          value: _alarm.vibrate,
          onChanged: (v) => setState(() => _alarm = _alarm.copyWith(vibrate: v)),
        ),
      ],
    );
  }

  // ============================================================
  // 未来 3 次响铃预览
  // ============================================================
  Widget _previewCard(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = DateRuleEngine.upcomingTriggers(_draft, count: 3);

    return _card(
      context,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Icon(Icons.preview_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('未来 3 次响铃',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
        if (upcoming.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text('当前规则下未来一年内不会响铃，请检查设置。'),
          )
        else
          ...upcoming.asMap().entries.map((e) {
            final index = e.key;
            final time = e.value;
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 12,
                backgroundColor:
                    theme.colorScheme.primary.withOpacity( index == 0 ? 1 : 0.18),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    color: index == 0
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              title: Text(
                DateRuleEngine.describeFull(time),
                style: TextStyle(
                  fontWeight:
                      index == 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
      ],
    );
  }

  // ============================================================
  // 删除按钮
  // ============================================================
  Widget _deleteButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: TextButton.icon(
        onPressed: () => _delete(context),
        icon: Icon(Icons.delete_outline, color: scheme.error),
        label: Text('删除这个闹钟', style: TextStyle(color: scheme.error)),
      ),
    );
  }

  /// 通用卡片容器
  Widget _card(BuildContext context, {required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity( 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(children: children),
    );
  }

  // ============================================================
  // 交互逻辑
  // ============================================================

  /// 打开条件一规则弹层
  Future<void> _pickRule() async {
    final result = await showRulePicker(context, _alarm);
    if (result != null) {
      setState(() => _alarm = result);
    }
  }

  /// 选择响铃时长
  Future<void> _pickRingDuration(BuildContext context) async {
    const options = [1, 2, 3, 5, 10, 15];
    final picked = await _showOptionSheet<int>(
      context,
      title: '响铃多久自动停',
      options: options,
      current: _alarm.ringDurationSeconds ~/ 60,
      labelOf: (v) => '$v 分钟',
    );
    if (picked != null) {
      setState(() => _alarm = _alarm.copyWith(ringDurationSeconds: picked * 60));
    }
  }

  /// 选择贪睡参数
  Future<void> _pickSnooze(BuildContext context) async {
    final minutes = await _showOptionSheet<int>(
      context,
      title: '贪睡时长',
      options: const [1, 3, 5, 10, 15, 20],
      current: _alarm.snoozeMinutes,
      labelOf: (v) => '$v 分钟',
    );
    if (minutes == null || !context.mounted) return;

    final times = await _showOptionSheet<int>(
      context,
      title: '最多贪睡几次',
      options: const [1, 2, 3, 5, 10],
      current: _alarm.maxSnoozeTimes,
      labelOf: (v) => '$v 次',
    );
    if (times == null) return;

    setState(() => _alarm =
        _alarm.copyWith(snoozeMinutes: minutes, maxSnoozeTimes: times));
  }

  /// 通用底部单选列表
  Future<T?> _showOptionSheet<T>(
    BuildContext context, {
    required String title,
    required List<T> options,
    required T current,
    required String Function(T) labelOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: Theme.of(sheetCtx).textTheme.titleMedium),
              ),
            ),
            ...options.map((o) => ListTile(
                  title: Text(labelOf(o)),
                  trailing: o == current
                      ? Icon(Icons.check,
                          color: Theme.of(sheetCtx).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(sheetCtx).pop(o),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 保存：写入数据库并同步给原生重新排程
  Future<void> _save() async {
    final alarm = _draft;

    // 校验：选了参数型规则却一个都没选，直接拦下来
    if (alarm.ruleType == DateRuleType.weeklyInterval &&
        alarm.weekdays.isEmpty) {
      _toast('请至少选择一个周几');
      return;
    }
    if (alarm.ruleType == DateRuleType.monthlyDay && alarm.monthDays.isEmpty) {
      _toast('请至少选择一个日期');
      return;
    }

    await AlarmStore.instance.save(alarm);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 删除
  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除闹钟'),
        content: Text('确定删除 ${_alarm.timeText}'
            '${_alarm.label.isEmpty ? '' : ' · ${_alarm.label}'} 吗？'),
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

    if (ok != true) return;
    await AlarmStore.instance.remove(_alarm.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
