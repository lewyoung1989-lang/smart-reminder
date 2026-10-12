import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_spacing.dart';
import '../domain/plan_models.dart';

class EditMedicationPlanSheet extends StatefulWidget {
  const EditMedicationPlanSheet({
    required this.detail,
    required this.onSave,
    super.key,
  });

  final PlanDetail detail;
  final Future<void> Function({
    required String medicineName,
    required String doseText,
    required List<String> times,
  }) onSave;

  static Future<bool?> show(
    BuildContext context, {
    required PlanDetail detail,
    required Future<void> Function({
      required String medicineName,
      required String doseText,
      required List<String> times,
    }) onSave,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditMedicationPlanSheet(
        detail: detail,
        onSave: onSave,
      ),
    );
  }

  @override
  State<EditMedicationPlanSheet> createState() =>
      _EditMedicationPlanSheetState();
}

class _EditMedicationPlanSheetState extends State<EditMedicationPlanSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _medicineController;
  late final TextEditingController _doseController;
  late List<String> _times;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final config = widget.detail.medicationConfig;
    final initialMedicine = config?.medicineName.isNotEmpty == true
        ? config!.medicineName
        : widget.detail.summary.title.replaceAll('服药提醒', '').trim();
    final initialDose = config?.doseText.isNotEmpty == true
        ? config!.doseText
        : (widget.detail.doseLabel ?? '');

    _medicineController = TextEditingController(text: initialMedicine);
    _doseController = TextEditingController(text: initialDose);

    if (config != null && config.times.isNotEmpty) {
      _times = List<String>.from(config.times);
    } else {
      // 从 notificationSchedule 或 reminderLabel 提取时间兜底
      final scheduled = widget.detail.notificationSchedule?.scheduledTimes;
      if (scheduled != null && scheduled.isNotEmpty) {
        _times = scheduled
            .map((dt) =>
                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}')
            .toSet()
            .toList()..sort();
      } else {
        final matches = RegExp(r'\b\d{1,2}:\d{2}\b')
            .allMatches(widget.detail.reminderLabel)
            .map((m) => m.group(0)!)
            .map((t) => t.length == 4 ? '0$t' : t)
            .toSet()
            .toList()..sort();
        _times = matches.isNotEmpty ? matches : ['08:00'];
      }
    }
  }

  @override
  void dispose() {
    _medicineController.dispose();
    _doseController.dispose();
    super.dispose();
  }

  Future<void> _editTime(int index) async {
    final current = _times[index].split(':');
    final initialHour = int.tryParse(current[0]) ?? 8;
    final initialMinute = current.length > 1 ? (int.tryParse(current[1]) ?? 0) : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        _times[index] = formatted;
        _times.sort();
      });
    }
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      if (!_times.contains(formatted)) {
        setState(() {
          _times.add(formatted);
          _times.sort();
        });
      }
    }
  }

  void _removeTime(int index) {
    if (_times.length <= 1) return;
    setState(() {
      _times.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_times.isEmpty) {
      setState(() => _errorMessage = '请至少保留一个提醒时间');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.onSave(
        medicineName: _medicineController.text.trim(),
        doseText: _doseController.text.trim(),
        times: _times,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = '保存失败，请检查输入或稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl + viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '编辑用药计划',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.alertCircle,
                            size: 16, color: theme.colorScheme.error),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextFormField(
                  controller: _medicineController,
                  decoration: const InputDecoration(
                    labelText: '药品名称',
                    hintText: '例如：盐酸普罗帕酮片',
                    prefixIcon: Icon(LucideIcons.pill, size: 20),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入药品名称';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _doseController,
                  decoration: const InputDecoration(
                    labelText: '单次剂量',
                    hintText: '例如：每次150mg 或 每次1片',
                    prefixIcon: Icon(LucideIcons.scale, size: 20),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入单次剂量';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '提醒时间',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (var i = 0; i < _times.length; i++)
                      InputChip(
                        avatar: const Icon(LucideIcons.clock, size: 16),
                        label: Text(
                          _times[i],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        deleteIcon: _times.length > 1
                            ? const Icon(LucideIcons.x, size: 14)
                            : null,
                        onDeleted: _times.length > 1 ? () => _removeTime(i) : null,
                        onPressed: () => _editTime(i),
                      ),
                    ActionChip(
                      avatar: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('添加时间'),
                      onPressed: _addTime,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '保存修改',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
