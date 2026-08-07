import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/ocr_job.dart';

enum MedicineOcrStage { capture, uploading, processing, review }

class MedicineOcrScreen extends StatefulWidget {
  const MedicineOcrScreen({
    required this.capture,
    required this.createJob,
    required this.getJob,
    required this.confirmJob,
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
  final Duration pollInterval;

  @override
  State<MedicineOcrScreen> createState() => _MedicineOcrScreenState();
}

class _MedicineOcrScreenState extends State<MedicineOcrScreen> {
  final _name = TextEditingController();
  final _specification = TextEditingController();
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

  @override
  void dispose() {
    _cancelPolling = true;
    for (final controller in [
      _name,
      _specification,
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
    if (job == null || !_canConfirm) {
      return;
    }
    // OCR 只提供候选，实际入库始终使用用户核对后的表单值。
    await widget.confirmJob(job.id, {
      'medicine_name': _name.text.trim(),
      'specification': _specification.text.trim(),
      'batch_number': _batch.text.trim(),
      'production_date':
          _production.text.trim().isEmpty ? null : _production.text.trim(),
      'expiry_date': _expiry.text.trim().isEmpty ? null : _expiry.text.trim(),
      'quantity': int.tryParse(_quantity.text) ?? 1,
    });
    if (!mounted) {
      return;
    }
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
      _error = null;
    });
  }

  Widget _photoSlot({
    required String kind,
    required String label,
    required List<int>? bytes,
  }) {
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
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        Uint8List.fromList(photoBytes),
                        key: Key('$kind-photo-preview'),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFE7ECE9),
                          child: Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filledTonal(
                        tooltip: retakeLabel,
                        onPressed: () => _capture(kind),
                        icon: const Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                  ],
                )
              : OutlinedButton.icon(
                  onPressed: () => _capture(kind),
                  icon: Icon(
                    kind == 'front'
                        ? Icons.camera_alt_outlined
                        : Icons.event_outlined,
                  ),
                  label: Text('拍摄$label'),
                ),
        ),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _captureView() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              const SizedBox(width: 12),
              Expanded(
                child: _photoSlot(
                  kind: 'expiry',
                  label: '有效期（可选）',
                  bytes: _expiryBytes,
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _frontBytes == null ? null : _start,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('开始识别'),
            ),
          ),
        ],
      );

  Widget _reviewView() => Form(
        onChanged: () => setState(() {}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '核对识别结果',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _canConfirm ? _confirm : null,
                icon: const Icon(Icons.check),
                label: const Text('确认入库'),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('药盒识别')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_stage == MedicineOcrStage.capture) _captureView(),
            if (_stage == MedicineOcrStage.uploading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在上传图片'),
                  ],
                ),
              ),
            if (_stage == MedicineOcrStage.processing)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在识别'),
                  ],
                ),
              ),
            if (_stage == MedicineOcrStage.review) _reviewView(),
          ],
        ),
      );
}
