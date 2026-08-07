import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/data/feature_unavailable_exception.dart';
import '../../../ui/components/app_content_state.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_property_row.dart';
import '../data/medicine_repository.dart';
import '../domain/medicine_models.dart';

class MedicineDetailScreen extends StatelessWidget {
  const MedicineDetailScreen({
    required this.detail,
    this.onDeleteBatch,
    super.key,
  });

  final MedicineDetail detail;
  final Future<void> Function(MedicineBatch batch)? onDeleteBatch;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppPageHeader(
                eyebrow: '家庭药箱',
                title: summary.name,
                actions: <Widget>[
                  if (Navigator.canPop(context))
                    IconButton(
                      tooltip: '返回药箱',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(LucideIcons.arrowLeft),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _StatusSummary(summary: summary),
              const SizedBox(height: AppSpacing.xl),
              _DetailSection(
                title: '药品信息',
                children: <Widget>[
                  AppPropertyRow(
                      label: '规格', value: Text(summary.specification)),
                  AppPropertyRow(
                    label: '库存',
                    value: Text('${summary.totalQuantity} 件'),
                  ),
                  AppPropertyRow(
                    label: '最近有效期',
                    value: Text(_formatDate(summary.nearestExpiry)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('批次信息', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              for (var index = 0;
                  index < detail.batches.length;
                  index += 1) ...[
                _BatchRow(
                  batch: detail.batches[index],
                  onDelete: onDeleteBatch,
                ),
                if (index < detail.batches.length - 1) const Divider(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MedicineDetailLoaderScreen extends StatefulWidget {
  const MedicineDetailLoaderScreen({
    required this.repository,
    required this.medicineId,
    this.onDeleteBatch,
    super.key,
  });

  final MedicineRepository repository;
  final String medicineId;
  final Future<void> Function(MedicineBatch batch)? onDeleteBatch;

  @override
  State<MedicineDetailLoaderScreen> createState() =>
      _MedicineDetailLoaderScreenState();
}

class _MedicineDetailLoaderScreenState
    extends State<MedicineDetailLoaderScreen> {
  MedicineDetail? _detail;
  Object? _error;
  var _isLoading = true;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.getById(widget.medicineId);
      if (!mounted || generation != _generation) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (detail != null) {
      return MedicineDetailScreen(
        detail: detail,
        onDeleteBatch: widget.onDeleteBatch,
      );
    }
    final state = switch (_error) {
      FeatureUnavailableException() => const AppContentState.unavailable(
          title: '药品详情暂时不可用',
          message: '请稍后再试',
        ),
      final Object? error when error != null => AppContentState.error(
          title: '药品详情加载失败',
          message: '请稍后再试',
          actionLabel: '重试',
          onAction: _load,
        ),
      _ => const AppContentState.loading(),
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppPageHeader(
                title: '药品详情',
                actions: <Widget>[
                  if (Navigator.canPop(context))
                    IconButton(
                      tooltip: '返回药箱',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(LucideIcons.arrowLeft),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: Center(
                    child:
                        _isLoading ? const AppContentState.loading() : state),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteBatchAction extends StatefulWidget {
  const _DeleteBatchAction({required this.batch, this.onDelete});

  final MedicineBatch batch;
  final Future<void> Function(MedicineBatch batch)? onDelete;

  @override
  State<_DeleteBatchAction> createState() => _DeleteBatchActionState();
}

class _DeleteBatchActionState extends State<_DeleteBatchAction> {
  var _isDeleting = false;

  Future<void> _confirmDelete() async {
    if (_isDeleting || widget.onDelete == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这个批次？'),
        content: const Text('删除后无法恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || widget.onDelete == null || !mounted) return;
    setState(() => _isDeleting = true);
    try {
      await widget.onDelete!(widget.batch);
      if (mounted && Navigator.canPop(context)) {
        await Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      key: Key('medicine-delete-batch-${widget.batch.id}'),
      onPressed: widget.onDelete == null || _isDeleting ? null : _confirmDelete,
      icon: const Icon(LucideIcons.trash2),
      label: const Text('删除批次'),
    );
    if (widget.onDelete != null) return button;
    return Semantics(
      button: true,
      enabled: false,
      label: '删除批次，服务尚未接入',
      child: ExcludeSemantics(child: button),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.summary});

  final MedicineSummary summary;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final status = _statusLabel(summary.status);
    final color = switch (summary.status) {
      MedicineStatus.active => semantic.success,
      MedicineStatus.expiring => semantic.warning,
      MedicineStatus.expired => Theme.of(context).colorScheme.error,
    };
    return Semantics(
      label: '状态：$status',
      child: Row(
        children: <Widget>[
          Icon(LucideIcons.pill, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text('状态：$status'),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        for (var index = 0; index < children.length; index += 1) ...[
          children[index],
          if (index < children.length - 1) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ],
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch, this.onDelete});

  final MedicineBatch batch;
  final Future<void> Function(MedicineBatch batch)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(batch.specification,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          if (batch.batchNumber.isNotEmpty) ...[
            Text('批号 ${batch.batchNumber}'),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text('${batch.sourceLabel} · ${batch.quantity} 件'),
          const SizedBox(height: AppSpacing.xs),
          Text('生产日期 ${_formatDate(batch.productionDate)}'),
          const SizedBox(height: AppSpacing.xs),
          Text('有效期至 ${_formatDate(batch.expiresOn)}'),
          const SizedBox(height: AppSpacing.sm),
          _DeleteBatchAction(batch: batch, onDelete: onDelete),
        ],
      ),
    );
  }
}

String medicineStatusLabel(MedicineStatus status) => _statusLabel(status);

String _statusLabel(MedicineStatus status) => switch (status) {
      MedicineStatus.active => '在用',
      MedicineStatus.expiring => '临期',
      MedicineStatus.expired => '已过期',
    };

String _formatDate(DateTime? value) =>
    value == null ? '未录入' : '${value.year}年${value.month}月${value.day}日';
