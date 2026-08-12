import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../quick_create/domain/voice_input_controller.dart';
import '../../../core/data/feature_unavailable_exception.dart';
import '../../../ui/components/app_content_state.dart';
import '../../../ui/components/app_list_row.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_segmented_control.dart';
import '../../../ui/components/app_status_banner.dart';
import '../data/api_medicine_repository.dart';
import '../data/medicine_cabinet_api.dart';
import '../data/medicine_repository.dart';
import '../domain/medicine_models.dart';
import '../domain/medicine_description_draft.dart';
import 'medicine_detail_screen.dart';

class MedicineCabinetScreen extends StatefulWidget {
  const MedicineCabinetScreen({
    this.repository,
    this.listBatches,
    this.deleteBatch,
    this.onDeleteBatch,
    this.onCapture,
    this.captureAvailability = MedicineCaptureAvailability.unavailable,
    this.onOpenSystemSettings,
    this.onOpenMedicine,
    this.onOpenSettings,
    this.onCorrectBatchExpiry,
    this.onCreateBatch,
    this.onParseDescription,
    this.voiceInputController,
    super.key,
  }) : assert(
          repository != null || listBatches != null,
          'A medicine repository or inventory loader is required.',
        );

  final MedicineRepository? repository;
  final InventoryBatchLoader? listBatches;
  final Future<void> Function(String batchId)? deleteBatch;
  final Future<void> Function(MedicineBatch batch)? onDeleteBatch;
  final Future<bool> Function()? onCapture;
  final MedicineCaptureAvailability captureAvailability;
  final VoidCallback? onOpenSystemSettings;
  final ValueChanged<MedicineSummary>? onOpenMedicine;
  final VoidCallback? onOpenSettings;
  final Future<void> Function(MedicineBatch batch, DateTime expiryDate)?
      onCorrectBatchExpiry;
  final Future<void> Function(MedicineBatchInput input)? onCreateBatch;
  final Future<MedicineDescriptionDraft> Function(String text)?
      onParseDescription;
  final VoiceInputController? voiceInputController;

  @override
  State<MedicineCabinetScreen> createState() => _MedicineCabinetScreenState();
}

class _MedicineCabinetScreenState extends State<MedicineCabinetScreen> {
  late MedicineRepository _repository;
  MedicineCollection? _collection;
  MedicineDetail? _selectedDetail;
  String? _selectedMedicineId;
  _ExpiryFilter _filter = _ExpiryFilter.all;
  String _query = '';
  Object? _error;
  Object? _detailError;
  var _isLoading = true;
  var _isDetailLoading = false;
  var _isOpeningCompactDetail = false;
  var _isCapturing = false;
  var _isOpeningEntry = false;
  var _wasExpanded = false;
  var _loadGeneration = 0;
  var _detailGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ??
        ApiMedicineRepository.fromLoader(widget.listBatches!);
    _load();
  }

  @override
  void didUpdateWidget(covariant MedicineCabinetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository &&
        widget.repository != null) {
      _repository = widget.repository!;
      _load(clearCollection: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final expanded =
        MediaQuery.sizeOf(context).width >= AppSpacing.breakpointExpanded;
    final enteredExpanded = expanded && !_wasExpanded;
    _wasExpanded = expanded;
    if (!enteredExpanded ||
        _collection == null ||
        _selectedMedicineId == null ||
        _selectedDetail != null ||
        _isDetailLoading) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSelectedDetail();
    });
  }

  Future<void> _load({bool clearCollection = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
      if (clearCollection) {
        _collection = null;
        _selectedMedicineId = null;
        _selectedDetail = null;
        _detailError = null;
        _isDetailLoading = false;
        _detailGeneration += 1;
      }
    });
    try {
      final collection = await _repository.load();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _collection = collection;
        _selectedMedicineId ??= _filtered(collection.items).firstOrNull?.id;
      });
      if (MediaQuery.sizeOf(context).width >= AppSpacing.breakpointExpanded) {
        await _loadSelectedDetail(collectionGeneration: generation);
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSelectedDetail({int? collectionGeneration}) async {
    final id = _selectedMedicineId;
    if (id == null) {
      setState(() {
        _selectedDetail = null;
        _detailError = null;
        _isDetailLoading = false;
      });
      return;
    }
    final generation = ++_detailGeneration;
    setState(() {
      _selectedDetail = null;
      _detailError = null;
      _isDetailLoading = true;
    });
    try {
      final detail = await _repository.getById(id);
      if (!mounted ||
          generation != _detailGeneration ||
          (collectionGeneration != null &&
              collectionGeneration != _loadGeneration) ||
          _selectedMedicineId != id) {
        return;
      }
      setState(() => _selectedDetail = detail);
    } catch (error) {
      if (!mounted ||
          generation != _detailGeneration ||
          (collectionGeneration != null &&
              collectionGeneration != _loadGeneration) ||
          _selectedMedicineId != id) {
        return;
      }
      setState(() => _detailError = error);
    } finally {
      if (mounted && generation == _detailGeneration) {
        setState(() => _isDetailLoading = false);
      }
    }
  }

  List<MedicineSummary> _filtered(List<MedicineSummary> medicines) {
    final query = _query.trim().toLowerCase();
    return medicines
        .where((medicine) => switch (_filter) {
              _ExpiryFilter.all => true,
              _ExpiryFilter.expiring =>
                medicine.status == MedicineStatus.expiring,
              _ExpiryFilter.expired =>
                medicine.status == MedicineStatus.expired,
            })
        .where((medicine) =>
            query.isEmpty ||
            medicine.name.toLowerCase().contains(query) ||
            medicine.specification.toLowerCase().contains(query))
        .toList();
  }

  void _setFilter(_ExpiryFilter filter) {
    setState(() {
      _filter = filter;
      _reconcileSelection();
    });
    if (MediaQuery.sizeOf(context).width >= AppSpacing.breakpointExpanded) {
      _loadSelectedDetail();
    }
  }

  void _setQuery(String query) {
    setState(() {
      _query = query;
      _reconcileSelection();
    });
    if (MediaQuery.sizeOf(context).width >= AppSpacing.breakpointExpanded) {
      _loadSelectedDetail();
    }
  }

  void _reconcileSelection() {
    final visible = _filtered(_collection?.items ?? const []);
    if (!visible.any((medicine) => medicine.id == _selectedMedicineId)) {
      _selectedMedicineId = visible.firstOrNull?.id;
      _selectedDetail = null;
    }
  }

  Future<void> _openMedicine(MedicineSummary medicine, bool expanded) async {
    if (widget.onOpenMedicine != null) {
      widget.onOpenMedicine!(medicine);
      return;
    }
    if (expanded) {
      setState(() {
        _selectedMedicineId = medicine.id;
        _selectedDetail = null;
      });
      await _loadSelectedDetail();
      return;
    }
    if (_isOpeningCompactDetail) return;
    setState(() => _isOpeningCompactDetail = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MedicineDetailLoaderScreen(
            repository: _repository,
            medicineId: medicine.id,
            onDeleteBatch: _deleteCallback,
            onCorrectBatchExpiry: _correctExpiryCallback,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpeningCompactDetail = false);
    }
  }

  Future<void> _deleteBatch(MedicineBatch batch) async {
    final delete = widget.onDeleteBatch;
    if (delete != null) {
      await delete(batch);
    } else {
      await widget.deleteBatch!(batch.id);
    }
    if (mounted) await _load(clearCollection: true);
  }

  Future<void> Function(MedicineBatch batch)? get _deleteCallback =>
      widget.onDeleteBatch == null && widget.deleteBatch == null
          ? null
          : _deleteBatch;

  Future<void> _correctBatchExpiry(
    MedicineBatch batch,
    DateTime expiryDate,
  ) async {
    final correct = widget.onCorrectBatchExpiry;
    if (correct == null) return;
    await correct(batch, expiryDate);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('有效期已修正')),
    );
    await _load(clearCollection: true);
  }

  Future<void> Function(MedicineBatch batch, DateTime expiryDate)?
      get _correctExpiryCallback =>
          widget.onCorrectBatchExpiry == null ? null : _correctBatchExpiry;

  Future<void> _capture() async {
    final capture = widget.onCapture;
    final canCapture =
        widget.captureAvailability == MedicineCaptureAvailability.ready ||
            widget.captureAvailability == MedicineCaptureAvailability.denied;
    if (capture == null || !canCapture || _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);
    try {
      final confirmed = await capture();
      if (confirmed && mounted) await _load(clearCollection: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('拍照录入失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _openEntrySheet() async {
    if (_isOpeningEntry) return;
    setState(() => _isOpeningEntry = true);
    try {
      final created = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => MedicineBatchEntrySheet(
          canCapture: widget.onCapture != null &&
              (widget.captureAvailability ==
                      MedicineCaptureAvailability.ready ||
                  widget.captureAvailability ==
                      MedicineCaptureAvailability.denied),
          isCapturing: _isCapturing,
          canCreateBatch: widget.onCreateBatch != null,
          voiceInputController: widget.voiceInputController,
          onCapture: () async {
            Navigator.of(sheetContext).pop(false);
            await _capture();
          },
          onCreate: _createBatch,
          onParseDescription: widget.onParseDescription,
          onCancel: () => Navigator.of(sheetContext).pop(false),
        ),
      );
      if (created == true && mounted) await _load(clearCollection: true);
    } finally {
      if (mounted) setState(() => _isOpeningEntry = false);
    }
  }

  Future<bool> _createBatch(MedicineBatchInput input) async {
    final create = widget.onCreateBatch;
    if (create == null) return false;
    try {
      await create(input);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('药品已录入')),
      );
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('录入失败，请检查内容后重试')),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final expanded =
        MediaQuery.sizeOf(context).width >= AppSpacing.breakpointExpanded;
    final content = _collectionContent(context, expanded);
    if (expanded && _collection != null && _error == null) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: <Widget>[
              SizedBox(width: 380, child: content),
              const VerticalDivider(width: 1),
              Expanded(child: _detailPane()),
            ],
          ),
        ),
      );
    }
    return Scaffold(body: SafeArea(child: content));
  }

  Widget _collectionContent(BuildContext context, bool expanded) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.xxl, AppSpacing.lg, AppSpacing.lg),
          sliver: SliverToBoxAdapter(
            child: AppPageHeader(
              title: '家庭药箱',
              largeTitle: true,
              actions: <Widget>[
                _EntryButton(
                  enabled: !_isOpeningEntry &&
                      (widget.onCapture != null ||
                          widget.onCreateBatch != null),
                  onPressed: _openEntrySheet,
                ),
                IconButton(
                  tooltip: '打开设置',
                  onPressed: widget.onOpenSettings,
                  icon: const Icon(LucideIcons.settings),
                ),
              ],
            ),
          ),
        ),
        ..._contentSlivers(context, expanded),
      ],
    );
  }

  List<Widget> _contentSlivers(BuildContext context, bool expanded) {
    final collection = _collection;
    final permissionRecovery = _permissionRecoverySlivers();
    if (collection == null) {
      if (_isLoading) {
        return [
          ...permissionRecovery,
          ..._stateSlivers(const AppContentState.loading())
        ];
      }
      if (_error is FeatureUnavailableException) {
        return [
          ...permissionRecovery,
          ..._stateSlivers(const AppContentState.unavailable(
            title: '药箱暂时不可用',
            message: '请稍后再试',
          )),
        ];
      }
      if (_error != null) {
        return [
          ...permissionRecovery,
          ..._stateSlivers(AppContentState.error(
            title: '药箱加载失败',
            message: '请检查网络后重试',
            actionLabel: '重试',
            onAction: _load,
          )),
        ];
      }
      return [
        ...permissionRecovery,
        ..._stateSlivers(const AppContentState.loading())
      ];
    }
    final visible = _filtered(collection.items);
    final counts = <_ExpiryFilter, int>{
      _ExpiryFilter.all: collection.items.length,
      _ExpiryFilter.expiring: collection.items
          .where((item) => item.status == MedicineStatus.expiring)
          .length,
      _ExpiryFilter.expired: collection.items
          .where((item) => item.status == MedicineStatus.expired)
          .length,
    };
    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: TextField(
            key: const Key('medicine-search'),
            onChanged: _setQuery,
            decoration: const InputDecoration(
              hintText: '搜索药品或规格',
              prefixIcon: Icon(LucideIcons.search),
            ),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: AppSegmentedControl<_ExpiryFilter>(
            value: _filter,
            options: <AppSegment<_ExpiryFilter>>[
              AppSegment(
                  value: _ExpiryFilter.all,
                  label: '全部',
                  count: counts[_ExpiryFilter.all]),
              AppSegment(
                  value: _ExpiryFilter.expiring,
                  label: '临期',
                  count: counts[_ExpiryFilter.expiring]),
              AppSegment(
                  value: _ExpiryFilter.expired,
                  label: '已过期',
                  count: counts[_ExpiryFilter.expired]),
            ],
            onChanged: _setFilter,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ...permissionRecovery,
    ];
    if (collection.isOffline) {
      slivers.add(const SliverPadding(
        padding:
            EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: AppStatusBanner(
            severity: AppStatusSeverity.offline,
            title: '正在显示上次同步药箱',
          ),
        ),
      ));
    }
    if (collection.isTruncated) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          sliver: SliverToBoxAdapter(
            child: AppStatusBanner(
              severity: AppStatusSeverity.info,
              title: '仅显示已加载的 ${collection.loadedBatchCount} 个库存批次',
              message: '数量和有效期状态仅基于这些批次',
            ),
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      slivers.addAll(_stateSlivers(const AppContentState.empty(
        title: '没有符合条件的药品',
        message: '调整搜索或有效期筛选后再查看',
      )));
      return slivers;
    }
    slivers.add(SliverPadding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
      sliver: SliverToBoxAdapter(
        child: Column(
          children: <Widget>[
            for (var index = 0; index < visible.length; index += 1)
              _MedicineRow(
                medicine: visible[index],
                position: _positionFor(index, visible.length),
                onTap: () => _openMedicine(visible[index], expanded),
              ),
          ],
        ),
      ),
    ));
    return slivers;
  }

  List<Widget> _stateSlivers(Widget state) => <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverToBoxAdapter(child: state),
        ),
      ];

  List<Widget> _permissionRecoverySlivers() {
    if (widget.captureAvailability !=
        MedicineCaptureAvailability.permanentlyDenied) {
      return const [];
    }
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: _PermissionRecoveryBanner(
            onOpenSystemSettings: widget.onOpenSystemSettings,
          ),
        ),
      ),
    ];
  }

  Widget _detailPane() {
    final detail = _selectedDetail;
    if (detail != null) {
      return MedicineDetailScreen(
        detail: detail,
        onDeleteBatch: _deleteCallback,
        onCorrectBatchExpiry: _correctExpiryCallback,
      );
    }
    if (_isDetailLoading) {
      return const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: AppContentState.loading());
    }
    if (_detailError is FeatureUnavailableException) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child:
            AppContentState.unavailable(title: '药品详情暂时不可用', message: '请稍后再试'),
      );
    }
    if (_detailError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppContentState.error(
          title: '药品详情加载失败',
          message: '请稍后再试',
          actionLabel: '重试',
          onAction: _loadSelectedDetail,
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: AppContentState.empty(title: '选择一个药品', message: '药品详情会显示在这里'),
    );
  }
}

class MedicineBatchInput {
  const MedicineBatchInput({
    required this.medicineName,
    required this.quantity,
    this.specification = '',
    this.batchNumber = '',
    this.productionDate,
    this.expiryDate,
  });

  final String medicineName;
  final String specification;
  final String batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final int quantity;
}

class _EntryButton extends StatelessWidget {
  const _EntryButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final button = TextButton.icon(
      onPressed: enabled ? () => onPressed() : null,
      icon: const Icon(LucideIcons.plus),
      label: const Text('录入'),
    );
    if (enabled) return button;
    return Semantics(
      button: true,
      enabled: false,
      label: '录入，录入服务尚未接入',
      hint: '录入服务尚未接入',
      child: ExcludeSemantics(child: button),
    );
  }
}

class MedicineBatchEntrySheet extends StatefulWidget {
  const MedicineBatchEntrySheet({
    required this.canCapture,
    required this.isCapturing,
    required this.canCreateBatch,
    this.voiceInputController,
    this.onCapture,
    this.onCreate,
    this.onParseDescription,
    this.onCancel,
    super.key,
  });

  final bool canCapture;
  final bool isCapturing;
  final bool canCreateBatch;
  final VoiceInputController? voiceInputController;
  final Future<void> Function()? onCapture;
  final Future<bool> Function(MedicineBatchInput input)? onCreate;
  final Future<MedicineDescriptionDraft> Function(String text)?
      onParseDescription;
  final VoidCallback? onCancel;

  @override
  State<MedicineBatchEntrySheet> createState() =>
      _MedicineBatchEntrySheetState();
}

class _MedicineBatchEntrySheetState extends State<MedicineBatchEntrySheet> {
  final _descriptionController = TextEditingController();
  final _nameController = TextEditingController();
  final _specificationController = TextEditingController();
  final _batchNumberController = TextEditingController();
  final _productionDateController = TextEditingController();
  final _expiryDateController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isVoiceActionInFlight = false;
  String? _error;
  String? _voiceActionError;
  String? _parseError;
  List<String> _ambiguities = const [];

  VoiceInputController? get _voice => widget.voiceInputController;

  @override
  void initState() {
    super.initState();
    _voice?.addListener(_onVoiceStateChanged);
  }

  @override
  void didUpdateWidget(covariant MedicineBatchEntrySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceInputController == widget.voiceInputController) return;
    oldWidget.voiceInputController?.removeListener(_onVoiceStateChanged);
    _voice?.addListener(_onVoiceStateChanged);
  }

  @override
  void dispose() {
    final voice = _voice;
    voice?.removeListener(_onVoiceStateChanged);
    if (voice?.phase == VoiceInputPhase.recording) {
      unawaited(_cancelVoiceOnDispose(voice!));
    }
    _descriptionController.dispose();
    _nameController.dispose();
    _specificationController.dispose();
    _batchNumberController.dispose();
    _productionDateController.dispose();
    _expiryDateController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _cancelVoiceOnDispose(VoiceInputController voice) async {
    try {
      await voice.cancel();
    } catch (_) {
      // Sheet cleanup cannot show UI after dismissal.
    }
  }

  void _onVoiceStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _parseDescription() async {
    final parse = widget.onParseDescription;
    final text = _descriptionController.text.trim();
    if (parse == null || _isParsing || text.isEmpty) {
      if (text.isEmpty) setState(() => _parseError = '请先输入或说出药品描述');
      return;
    }
    setState(() {
      _isParsing = true;
      _parseError = null;
      _ambiguities = const [];
    });
    try {
      final draft = await parse(text);
      if (!mounted) return;
      if (draft.medicineName != null) {
        _nameController.text = draft.medicineName!;
      }
      if (draft.specification != null) {
        _specificationController.text = draft.specification!;
      }
      if (draft.batchNumber != null) {
        _batchNumberController.text = draft.batchNumber!;
      }
      if (draft.productionDate != null) {
        _productionDateController.text = _formatDate(draft.productionDate!);
      }
      if (draft.expiryDate != null) {
        _expiryDateController.text = _formatDate(draft.expiryDate!);
      }
      if (draft.quantity != null) {
        _quantityController.text = draft.quantity!.toString();
      }
      setState(() => _ambiguities = draft.ambiguities);
    } catch (_) {
      if (mounted) setState(() => _parseError = '智能解析失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  Future<void> _handleVoiceAction() async {
    final voice = _voice;
    if (voice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('语音输入暂不可用'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_isVoiceActionInFlight ||
        (voice.phase != VoiceInputPhase.idle &&
            voice.phase != VoiceInputPhase.recording)) {
      return;
    }
    setState(() {
      _isVoiceActionInFlight = true;
      _voiceActionError = null;
    });
    try {
      if (voice.phase == VoiceInputPhase.idle) {
        await voice.start();
      } else {
        final transcript = await voice.stopAndTranscribe();
        if (!mounted || transcript == null || transcript.trim().isEmpty) {
          return;
        }
        _descriptionController.text = transcript.trim();
        setState(() => _error = null);
        await _parseDescription();
      }
    } catch (_) {
      if (mounted) setState(() => _voiceActionError = '语音输入失败，请重试');
    } finally {
      if (mounted) setState(() => _isVoiceActionInFlight = false);
    }
  }

  Future<void> _retryVoice() async {
    final voice = _voice;
    if (voice == null || _isVoiceActionInFlight) return;
    setState(() {
      _isVoiceActionInFlight = true;
      _voiceActionError = null;
    });
    try {
      await voice.retry();
    } catch (_) {
      if (mounted) setState(() => _voiceActionError = '语音输入失败，请重试');
    } finally {
      if (mounted) setState(() => _isVoiceActionInFlight = false);
    }
  }

  Future<void> _save() async {
    final onCreate = widget.onCreate;
    if (onCreate == null || _isSaving) return;
    final quantity = int.tryParse(_quantityController.text.trim());
    final productionDate = _parseDateInput(_productionDateController.text);
    final expiryDate = _parseDateInput(_expiryDateController.text);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写药品名称');
      return;
    }
    if (quantity == null || quantity < 1) {
      setState(() => _error = '数量需要是大于 0 的整数');
      return;
    }
    if (_productionDateController.text.trim().isNotEmpty &&
        productionDate == null) {
      setState(() => _error = '生产日期格式请填写 YYYY-MM-DD');
      return;
    }
    if (_expiryDateController.text.trim().isNotEmpty && expiryDate == null) {
      setState(() => _error = '有效期格式请填写 YYYY-MM-DD');
      return;
    }
    if (productionDate != null &&
        expiryDate != null &&
        expiryDate.isBefore(productionDate)) {
      setState(() => _error = '有效期不能早于生产日期');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final created = await onCreate(MedicineBatchInput(
        medicineName: name,
        specification: _specificationController.text.trim(),
        batchNumber: _batchNumberController.text.trim(),
        productionDate: productionDate,
        expiryDate: expiryDate,
        quantity: quantity,
      ));
      if (!mounted || !created) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await _voice?.cancel();
    } catch (_) {
      // The sheet still closes because abandoning input must not retain focus.
    }
    if (!mounted) return;
    final onCancel = widget.onCancel;
    if (onCancel != null) {
      onCancel();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _voice?.phase ?? VoiceInputPhase.idle;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Material(
          key: const Key('medicine-entry-sheet'),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '录入药品',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: TextButton(
                              onPressed: _cancel,
                              child: const Text('取消'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          key: const Key('medicine-entry-capture'),
                          onPressed: widget.canCapture && !widget.isCapturing
                              ? widget.onCapture
                              : null,
                          icon: const Icon(LucideIcons.camera),
                          label: const Text('拍照识别'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('medicine-entry-description'),
                        controller: _descriptionController,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 300,
                        decoration: const InputDecoration(
                          labelText: '文字或语音描述',
                          hintText: '例如：录入布洛芬胶囊 0.3g 2盒，有效期到2027年1月1日',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          key: const Key('medicine-entry-parse'),
                          onPressed: widget.onParseDescription != null &&
                                  !_isParsing &&
                                  !_isSaving
                              ? _parseDescription
                              : null,
                          icon: _isParsing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(LucideIcons.sparkles),
                          label: Text(_isParsing ? '正在智能解析' : '智能解析'),
                        ),
                      ),
                      if (_parseError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _parseError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_ambiguities.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '请确认：${_ambiguities.join('；')}',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _VoiceStatus(
                        voice: _voice,
                        phase: phase,
                        inFlight: _isVoiceActionInFlight,
                        actionError: _voiceActionError,
                        onRetry: _retryVoice,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              key: const Key('medicine-entry-voice'),
                              onPressed: _isSaving ||
                                      _isParsing ||
                                      _isVoiceActionInFlight ||
                                      phase == VoiceInputPhase.transcribing ||
                                      phase == VoiceInputPhase.failure
                                  ? null
                                  : _handleVoiceAction,
                              icon: Icon(phase == VoiceInputPhase.recording
                                  ? LucideIcons.square
                                  : LucideIcons.mic),
                              label: Text(phase == VoiceInputPhase.recording
                                  ? '停止录音'
                                  : '语音录入'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('medicine-entry-name'),
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '药品名称 *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('medicine-entry-specification'),
                        controller: _specificationController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '规格',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('medicine-entry-batch-number'),
                        controller: _batchNumberController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '批号',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('medicine-entry-production-date'),
                              controller: _productionDateController,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: '生产日期',
                                hintText: 'YYYY-MM-DD',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              key: const Key('medicine-entry-expiry-date'),
                              controller: _expiryDateController,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: '有效期',
                                hintText: 'YYYY-MM-DD',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('medicine-entry-quantity'),
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '数量 *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          key: const Key('medicine-entry-save'),
                          onPressed: widget.canCreateBatch && !_isSaving
                              ? _save
                              : null,
                          child: _isSaving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('保存到药箱'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceStatus extends StatelessWidget {
  const _VoiceStatus({
    required this.voice,
    required this.phase,
    required this.inFlight,
    required this.actionError,
    required this.onRetry,
  });

  final VoiceInputController? voice;
  final VoiceInputPhase phase;
  final bool inFlight;
  final String? actionError;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (inFlight) return const Text('正在处理语音输入');
    if (phase == VoiceInputPhase.failure || actionError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              voice?.errorMessage ?? actionError ?? '语音输入失败',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          SizedBox(
            height: 44,
            child: TextButton(onPressed: onRetry, child: const Text('重试')),
          ),
        ],
      );
    }
    return switch (phase) {
      VoiceInputPhase.recording =>
        Text('正在录音 ${_formatDuration(voice!.elapsed)}'),
      VoiceInputPhase.transcribing => const Text('正在转写'),
      VoiceInputPhase.idle => const SizedBox.shrink(),
      VoiceInputPhase.failure => const SizedBox.shrink(),
    };
  }
}

class _PermissionRecoveryBanner extends StatelessWidget {
  const _PermissionRecoveryBanner({this.onOpenSystemSettings});

  final VoidCallback? onOpenSystemSettings;

  @override
  Widget build(BuildContext context) {
    if (onOpenSystemSettings != null) {
      return AppStatusBanner(
        severity: AppStatusSeverity.warning,
        title: '需要相机权限才能拍照录入',
        actionLabel: '打开设置',
        onAction: onOpenSystemSettings,
      );
    }
    return Semantics(
      container: true,
      button: true,
      enabled: false,
      label: '打开设置，服务尚未接入',
      child: ExcludeSemantics(
        child: const AppStatusBanner(
          severity: AppStatusSeverity.warning,
          title: '需要相机权限才能拍照录入',
          message: '打开设置服务尚未接入',
        ),
      ),
    );
  }
}

class _MedicineRow extends StatelessWidget {
  const _MedicineRow(
      {required this.medicine, required this.position, required this.onTap});

  final MedicineSummary medicine;
  final AppListRowPosition position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final color = switch (medicine.status) {
      MedicineStatus.active => semantic.success,
      MedicineStatus.expiring => semantic.warning,
      MedicineStatus.expired => Theme.of(context).colorScheme.error,
      MedicineStatus.unknown => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return AppListRow(
      icon: LucideIcons.pill,
      title: medicine.name,
      subtitle:
          '${medicine.specification} · ${medicine.totalQuantity} 件 · ${_formatExpiry(medicine.nearestExpiry)}',
      statusText: medicineStatusLabel(medicine.status),
      statusColor: color,
      position: position,
      onTap: onTap,
    );
  }
}

enum _ExpiryFilter { all, expiring, expired }

AppListRowPosition _positionFor(int index, int length) =>
    switch ((index, length)) {
      (_, 1) => AppListRowPosition.single,
      (0, _) => AppListRowPosition.first,
      (final value, final total) when value == total - 1 =>
        AppListRowPosition.last,
      _ => AppListRowPosition.middle,
    };

String _formatExpiry(DateTime? value) =>
    value == null ? '有效期未录入' : '有效期至 ${value.year}/${value.month}/${value.day}';

String _formatDuration(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime? _parseDateInput(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final match = RegExp(r'^(20\d{2})[-/.年](\d{1,2})(?:[-/.月](\d{1,2})日?)?$')
      .firstMatch(trimmed);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = match.group(3) == null
      ? DateUtils.getDaysInMonth(year, month)
      : int.parse(match.group(3)!);
  try {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  } catch (_) {
    return null;
  }
}

extension on List<MedicineSummary> {
  MedicineSummary? get firstOrNull => isEmpty ? null : first;
}
