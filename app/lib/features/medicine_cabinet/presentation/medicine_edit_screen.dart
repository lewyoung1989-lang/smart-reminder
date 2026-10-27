import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/medicine_cabinet_api.dart';
import '../domain/medicine_models.dart';

class MedicineEditScreen extends StatefulWidget {
  const MedicineEditScreen({
    required this.summary,
    required this.batch,
    required this.onSave,
    super.key,
  });

  final MedicineSummary summary;
  final MedicineBatch batch;
  final MedicineBatchUpdater onSave;

  @override
  State<MedicineEditScreen> createState() => _MedicineEditScreenState();
}

class _MedicineEditScreenState extends State<MedicineEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late bool _precise;
  var _saving = false;
  var _conflict = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final batch = widget.batch;
    _precise = batch.unitsPerPackage != null;
    final values = {
      'name': widget.summary.name,
      'specification': widget.summary.specification,
      'manufacturer': widget.summary.manufacturer,
      'quantity': '${batch.quantity}',
      'expiry': _date(batch.expiresOn),
      'production': _date(batch.productionDate),
      'package': batch.packageUnit,
      'perPackage':
          batch.unitsPerPackage == null ? '' : _number(batch.unitsPerPackage!),
      'unit': batch.unitName,
      'loose': _number(batch.looseUnits),
    };
    for (final entry in values.entries) {
      _fields[entry.key] = TextEditingController(text: entry.value);
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _text(String name) => _fields[name]!.text.trim();

  Future<void> _save() async {
    if (_saving || _conflict || !_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
          widget.batch,
          MedicineBatchEdit(
            medicineName: _text('name'),
            specification: _text('specification'),
            manufacturer: _text('manufacturer'),
            quantity: int.parse(_text('quantity')),
            expiryDate: DateTime.tryParse(_text('expiry')),
            productionDate: DateTime.tryParse(_text('production')),
            packageUnit: _precise ? _text('package') : '',
            unitsPerPackage:
                _precise ? double.parse(_text('perPackage')) : null,
            unitName: _precise ? _text('unit') : '',
            looseUnits: _precise ? double.parse(_text('loose')) : 0,
          ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _conflict =
            error is MedicineCabinetApiException && error.statusCode == 409;
        _error = _errorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is MedicineCabinetApiException) {
      if (error.statusCode == 409) {
        return '库存已被更新，请返回药箱刷新后重新编辑，避免覆盖最新余量。';
      }
      if (error.statusCode == 400) {
        try {
          final data = jsonDecode(error.body) as Map<String, dynamic>;
          return data.values
              .map((value) => value is List ? value.join('，') : '$value')
              .join('\n');
        } catch (_) {
          return '请检查药品信息和库存数量后重试。';
        }
      }
      if (error.statusCode == 403 || error.statusCode == 404) {
        return '该药品已删除或你已无权修改，请返回药箱刷新。';
      }
    }
    return '保存失败，请检查网络后重试。已填写内容会保留。';
  }

  Widget _field(
    String name,
    String label, {
    TextInputType? keyboard,
    int? maxLength,
    String? helper,
    String? Function(String)? validate,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          key: Key('medicine-edit-$name'),
          controller: _fields[name],
          enabled: !_saving,
          keyboardType: keyboard,
          maxLength: maxLength,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              helperMaxLines: 4,
              counterText: ''),
          validator: (value) => validate?.call(value?.trim() ?? ''),
        ),
      );

  String? _dateError(String value) {
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null || _date(parsed) != value
        ? '请填写 YYYY-MM-DD，例如 2028-06-30'
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('编辑药品'),
            actions: [
              TextButton(
                onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: const Text('收起键盘'),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('药品资料', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  const Text('资料修改会同步到这款药品的其他库存记录。照片和关联用药计划会保留。'),
                  const SizedBox(height: 16),
                  _field('name', '药品名称',
                      maxLength: 200,
                      validate: (value) => value.isEmpty ? '请填写药品名称' : null),
                  _field('specification', '规格', maxLength: 120),
                  _field('manufacturer', '生产公司（选填）', maxLength: 200),
                  Text('当前库存', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  _field('quantity', _precise ? '完整包装数量' : '库存件数',
                      keyboard: TextInputType.number,
                      helper: _precise
                          ? '只填写未拆开的包装数，已开封余量在下方填写。'
                          : '填写现在实际剩余的件数，可填 0。', validate: (value) {
                    final parsed = int.tryParse(value);
                    return parsed == null || parsed < 0 || parsed > 9999
                        ? '请输入 0～9999 的整数'
                        : null;
                  }),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('精确管理盒内余量'),
                    subtitle: const Text('用于按片、粒等单位扣减库存'),
                    value: _precise,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _precise = value),
                  ),
                  if (_precise) ...[
                    _field('package', '包装单位',
                        maxLength: 16,
                        helper: '例如 盒、瓶',
                        validate: (value) => value.isEmpty ? '请填写包装单位' : null),
                    _field('perPackage', '每包装含量',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true), validate: (value) {
                      final parsed = double.tryParse(value);
                      return parsed == null ||
                              !parsed.isFinite ||
                              parsed <= 0 ||
                              parsed > 9999999.999 ||
                              !_validDecimal(value)
                          ? '请输入大于 0 的数量，最多三位小数'
                          : null;
                    }),
                    _field('unit', '计量单位',
                        maxLength: 16,
                        helper: '请与用药计划剂量单位一致，例如 片、粒、毫升',
                        validate: (value) => value.isEmpty ? '请填写计量单位' : null),
                    _field('loose', '已开封剩余量',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true), validate: (value) {
                      final parsed = double.tryParse(value);
                      final perPackage = double.tryParse(_text('perPackage'));
                      return parsed == null ||
                              !parsed.isFinite ||
                              parsed < 0 ||
                              !_validDecimal(value) ||
                              (perPackage != null && parsed >= perPackage)
                          ? '请填写小于每包装含量的余量，最多三位小数'
                          : null;
                    }),
                  ],
                  _field('production', '生产日期（选填）',
                      keyboard: TextInputType.datetime, validate: _dateError),
                  _field('expiry', '有效期（选填）',
                      keyboard: TextInputType.datetime,
                      helper: '格式 YYYY-MM-DD；留空表示未知。', validate: (value) {
                    final error = _dateError(value);
                    if (error != null) return error;
                    final production = DateTime.tryParse(_text('production'));
                    final expiry = DateTime.tryParse(value);
                    return production != null &&
                            expiry != null &&
                            expiry.isBefore(production)
                        ? '有效期不能早于生产日期'
                        : null;
                  }),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    ),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : _conflict
                            ? () => Navigator.of(context).pop(false)
                            : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _saving
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                  SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                  SizedBox(width: 12),
                                  Text('正在保存…'),
                                ])
                          : Text(_conflict ? '返回药箱刷新' : '保存修改'),
                    ),
                  ),
                ]),
          ),
        ),
      );

  static bool _validDecimal(String value) =>
      RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(value);
  static String _number(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';
  static String _date(DateTime? value) => value == null
      ? ''
      : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
