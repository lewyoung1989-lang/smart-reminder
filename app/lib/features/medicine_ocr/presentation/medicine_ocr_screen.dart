import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_status_banner.dart';
import '../domain/ocr_job.dart';
import '../../medicine_cabinet/domain/inventory_batch.dart';

enum MedicineOcrStage { capture, uploading, processing, review }

class MedicineOcrScreen extends StatefulWidget {
  const MedicineOcrScreen({
    required this.capture,
    required this.createJob,
    required this.getJob,
    required this.confirmJob,
    this.scope = MedicineCabinetScope.personal,
    this.pollInterval = const Duration(seconds: 2),
    super.key,
  });

  final Future<List<int>?> Function(String kind) capture;
  final Future<OcrJob> Function({
    required List<int> frontBytes,
    List<int>? expiryBytes,
  }) createJob;
  final Future<OcrJob> Function(String id) getJob;
  final Future<void> Function(String id, Map<String, Object?> fields)
      confirmJob;
  final MedicineCabinetScope scope;
  final Duration pollInterval;

  @override
  State<MedicineOcrScreen> createState() => _MedicineOcrScreenState();
}

class _MedicineOcrScreenState extends State<MedicineOcrScreen> {
  final _name = TextEditingController();
  final _specification = TextEditingController();
  final _manufacturer = TextEditingController();
  final _batch = TextEditingController();
  final _production = TextEditingController();
  final _expiry = TextEditingController();
  final _quantity = TextEditingController(text: '1');

  MedicineOcrStage _stage = MedicineOcrStage.capture;
  List<int>? _frontBytes;
  List<int>? _expiryBytes;
  OcrJob? _job;
  String? _error;
  bool _cancelPolling = false;
  bool _isConfirming = false;

  @override
  void dispose() {
    _cancelPolling = true;
    for (final controller in [
      _name,
      _specification,
      _manufacturer,
      _batch,
      _production,
      _expiry,
      _quantity,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _capture(String kind) async {
    try {
      final bytes = await widget.capture(kind);
      if (!mounted) {
        return;
      }
      if (bytes == null) {
        if (_error != null) {
          setState(() => _error = null);
        }
        return;
      }
      setState(() {
        if (kind == 'front') {
          _frontBytes = bytes;
        }
        if (kind == 'expiry') {
          _expiryBytes = bytes;
        }
        _error = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '无法打开相机，请检查相机权限后重试';
      });
    }
  }

  Future<void> _start() async {
    final front = _frontBytes;
    if (front == null || _stage != MedicineOcrStage.capture) {
      return;
    }
    setState(() {
      _stage = MedicineOcrStage.uploading;
      _error = null;
    });

    try {
      final created = await widget.createJob(
        frontBytes: front,
        expiryBytes: _expiryBytes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _job = created;
        _stage = MedicineOcrStage.processing;
      });

      // 轮询只持续一分钟；页面销毁或服务端进入终态后立即停止。
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!_cancelPolling && DateTime.now().isBefore(deadline)) {
        final current = await widget.getJob(created.id);
        if (!mounted || _cancelPolling) {
          return;
        }
        if (current.status == 'succeeded' && current.candidate != null) {
          _loadCandidate(current.candidate!);
          setState(() {
            _job = current;
            _stage = MedicineOcrStage.review;
          });
          return;
        }
        if (current.status == 'failed') {
          setState(() {
            _stage = MedicineOcrStage.capture;
            _error = '识别失败，可以重拍或手动录入';
          });
          return;
        }
        await Future<void>.delayed(widget.pollInterval);
      }
      if (mounted) {
        setState(() {
          _stage = MedicineOcrStage.capture;
          _error = '识别仍在处理中，请稍后重试';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _stage = MedicineOcrStage.capture;
          _error = '上传失败，请检查网络后重试';
        });
      }
    }
  }

  void _loadCandidate(OcrCandidate value) {
    _name.text = value.medicineName;
    _specification.text = value.specification;
    _manufacturer.text = value.manufacturer;
    _batch.text = value.batchNumber;
    _production.text =
        value.productionDate?.toIso8601String().substring(0, 10) ?? '';
    _expiry.text = value.expiryDate?.toIso8601String().substring(0, 10) ?? '';
  }

  bool get _canConfirm {
    if (_name.text.trim().isEmpty) {
      return false;
    }
    final production = DateTime.tryParse(_production.text.trim());
    final expiry = DateTime.tryParse(_expiry.text.trim());
    return production == null || expiry == null || !expiry.isBefore(production);
  }

  Future<void> _confirm() async {
    final job = _job;
    if (job == null || !_canConfirm || _isConfirming) {
      return;
    }
    setState(() {
      _isConfirming = true;
      _error = null;
    });
    try {
      // OCR 只提供候选，实际入库始终使用用户核对后的表单值。
      await widget.confirmJob(job.id, {
        'scope': widget.scope.apiValue,
        'medicine_name': _name.text.trim(),
        'specification': _specification.text.trim(),
        'manufacturer': _manufacturer.text.trim(),
        'retain_front_photo': true,
        'batch_number': _batch.text.trim(),
        'production_date':
            _production.text.trim().isEmpty ? null : _production.text.trim(),
        'expiry_date': _expiry.text.trim().isEmpty ? null : _expiry.text.trim(),
        'quantity': int.tryParse(_quantity.text) ?? 1,
      });
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop(true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入药箱')),
      );
      setState(() {
        _stage = MedicineOcrStage.capture;
        _frontBytes = null;
        _expiryBytes = null;
        _job = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '入库失败，请检查网络后重试');
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Widget _photoSlot({
    required String kind,
    required String label,
    required List<int>? bytes,
  }) {
    final theme = Theme.of(context);
    final photoBytes = bytes;
    final retakeLabel = kind == 'front' ? '重新拍摄药盒正面' : '重新拍摄有效期';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: photoBytes != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      child: Image.memory(
                        Uint8List.fromList(photoBytes),
                        key: Key('$kind-photo-preview'),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: theme.colorScheme.surfaceContainer,
                          child: const Icon(LucideIcons.image),
                        ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.xs,
                      right: AppSpacing.xs,
                      child: IconButton.filledTonal(
                        tooltip: retakeLabel,
                        onPressed: () => _capture(kind),
                        icon: const Icon(LucideIcons.camera),
                      ),
                    ),
                  ],
                )
              : OutlinedButton.icon(
                  onPressed: () => _capture(kind),
                  icon: Icon(
                    kind == 'front'
                        ? LucideIcons.camera
                        : LucideIcons.calendarDays,
                  ),
                  label: Text('拍摄$label'),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(label,
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _captureView() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('拍摄药盒', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '药盒正面用于识别名称和规格；有效期照片可以补充日期信息。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _photoSlot(
                  kind: 'front',
                  label: '药盒正面',
                  bytes: _frontBytes,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _photoSlot(
                  kind: 'expiry',
                  label: '有效期（可选）',
                  bytes: _expiryBytes,
                ),
              ),
            ],
          ),
        ],
      );

  Widget _reviewView() => Form(
        onChanged: () => setState(() {}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '请检查以下信息，确认后才会加入药箱。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            TextFormField(
              key: const Key('medicine-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: '药品名称'),
            ),
            TextFormField(
              controller: _specification,
              decoration: const InputDecoration(labelText: '规格'),
            ),
            TextFormField(
              key: const Key('medicine-manufacturer'),
              controller: _manufacturer,
              decoration: const InputDecoration(labelText: '生产公司（选填）'),
            ),
            TextFormField(
              controller: _batch,
              decoration: const InputDecoration(labelText: '批号'),
            ),
            TextFormField(
              controller: _production,
              decoration: const InputDecoration(
                labelText: '生产日期',
                hintText: 'YYYY-MM-DD',
              ),
            ),
            TextFormField(
              controller: _expiry,
              decoration: const InputDecoration(
                labelText: '有效期',
                hintText: 'YYYY-MM-DD',
              ),
            ),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '数量'),
            ),
          ],
        ),
      );

  AppStatusBanner? _statusBanner() {
    if (_error != null) {
      return AppStatusBanner(
        severity: AppStatusSeverity.error,
        title: _error!,
        message: '请保留已拍摄的照片，处理后可以再次尝试。',
      );
    }
    return switch (_stage) {
      MedicineOcrStage.uploading => const AppStatusBanner(
          severity: AppStatusSeverity.info,
          title: '正在上传药盒照片',
          message: '请保持此页面打开。',
        ),
      MedicineOcrStage.processing => const AppStatusBanner(
          severity: AppStatusSeverity.info,
          title: '正在识别药盒信息',
          message: '识别结果需要你核对后才会加入药箱。',
        ),
      MedicineOcrStage.capture || MedicineOcrStage.review => null,
    };
  }

  Widget _bottomAction() {
    final (label, icon, onPressed) = switch (_stage) {
      MedicineOcrStage.capture => (
          '开始识别',
          LucideIcons.scanLine,
          _frontBytes == null ? null : _start,
        ),
      MedicineOcrStage.review => (
          _isConfirming ? '正在入库' : '确认入库',
          _isConfirming ? LucideIcons.loaderCircle : LucideIcons.check,
          _canConfirm && !_isConfirming ? _confirm : null,
        ),
      MedicineOcrStage.uploading => ('正在上传', LucideIcons.upload, null),
      MedicineOcrStage.processing => ('正在识别', LucideIcons.scanLine, null),
    };
    return FilledButton.icon(
      onPressed: onPressed,
      icon: _isConfirming && _stage == MedicineOcrStage.review
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusBanner();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            AppPageHeader(
              eyebrow: '家庭药箱',
              title: _stage == MedicineOcrStage.review ? '核对识别结果' : '药盒识别',
              actions: [
                if (Navigator.canPop(context))
                  IconButton(
                    tooltip: '返回药箱',
                    onPressed: _stage == MedicineOcrStage.uploading ||
                            _stage == MedicineOcrStage.processing
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(LucideIcons.arrowLeft),
                  ),
              ],
            ),
            if (status != null) ...[
              const SizedBox(height: AppSpacing.xl),
              status,
            ],
            const SizedBox(height: AppSpacing.xl),
            if (_stage == MedicineOcrStage.capture) _captureView(),
            if (_stage == MedicineOcrStage.review) _reviewView(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(height: 48, child: _bottomAction()),
        ),
      ),
    );
  }
}
