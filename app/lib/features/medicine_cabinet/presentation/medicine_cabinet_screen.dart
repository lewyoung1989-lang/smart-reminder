import 'dart:async';
import 'dart:typed_data';

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
import '../domain/inventory_batch.dart';
import '../domain/medicine_description_draft.dart';
import 'medicine_detail_screen.dart';

class MedicineCabinetScreen extends StatefulWidget {
  const MedicineCabinetScreen({
    this.repository,
    this.listBatches,
    this.deleteBatch,
    this.onDeleteBatch,
    this.onCapture,
    this.onCapturePhoto,
    this.captureAvailability = MedicineCaptureAvailability.unavailable,
    this.onOpenSystemSettings,
    this.onOpenMedicine,
    this.onOpenSettings,
    this.onCorrectBatchExpiry,
    this.onCreateBatch,
    this.onParseDescription,
    this.voiceInputController,
    this.familyMembershipRevision = 0,
    this.hasFamilyMembership,
    super.key,
  }) : assert(
          repository != null || listBatches != null,
          'A medicine repository or inventory loader is required.',
        );

  final MedicineRepository? repository;
  final InventoryBatchLoader? listBatches;
  final Future<void> Function(String batchId)? deleteBatch;
  final Future<void> Function(MedicineBatch batch)? onDeleteBatch;
  final Future<bool> Function(MedicineCabinetScope scope)? onCapture;
  final Future<List<int>?> Function()? onCapturePhoto;
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
  final int familyMembershipRevision;
  final bool? hasFamilyMembership;

  @override
  State<MedicineCabinetScreen> createState() => _MedicineCabinetScreenState();
}

class _MedicineCabinetScreenState extends State<MedicineCabinetScreen> {
  final _searchController = TextEditingController();
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
  var _scope = MedicineCabinetScope.personal;
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MedicineCabinetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    var shouldReload = false;
    if (oldWidget.repository != widget.repository &&
        widget.repository != null) {
      _repository = widget.repository!;
      shouldReload = true;
    }
    if (oldWidget.familyMembershipRevision != widget.familyMembershipRevision &&
        widget.hasFamilyMembership != null) {
      _scope = widget.hasFamilyMembership!
          ? MedicineCabinetScope.family
          : MedicineCabinetScope.personal;
      shouldReload = true;
    }
    if (shouldReload) _load(clearCollection: true);
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
      final collection = await _repository.load(scope: _scope);
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
    return _filterByExpiry(_filterByQuery(medicines, query), _filter).toList();
  }

  Iterable<MedicineSummary> _filterByQuery(
    Iterable<MedicineSummary> medicines,
    String query,
  ) {
    if (query.isEmpty) return medicines;
    return medicines.where((medicine) =>
        medicine.name.toLowerCase().contains(query) ||
        medicine.specification.toLowerCase().contains(query));
  }

  Iterable<MedicineSummary> _filterByExpiry(
    Iterable<MedicineSummary> medicines,
    _ExpiryFilter filter,
  ) {
    return medicines.where((medicine) => switch (filter) {
          _ExpiryFilter.all => true,
          _ExpiryFilter.expiring => medicine.status == MedicineStatus.expiring,
          _ExpiryFilter.expired => medicine.status == MedicineStatus.expired,
        });
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

  void _clearQuery() {
    _searchController.clear();
    _setQuery('');
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
      final confirmed = await capture(_scope);
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
          scope: _scope,
          voiceInputController: widget.voiceInputController,
          onCapture: () async {
            Navigator.of(sheetContext).pop(false);
            await _capture();
          },
          onCreate: _createBatch,
          onCapturePhoto: widget.onCapturePhoto,
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
    final collection = _collection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: AppPageHeader(
            title: '药箱',
            largeTitle: true,
            actions: <Widget>[
              _EntryButton(
                enabled: !_isOpeningEntry &&
                    (widget.onCapture != null || widget.onCreateBatch != null),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: AppSegmentedControl<MedicineCabinetScope>(
            key: const ValueKey('cabinet-scope-tabs'),
            value: _scope,
            options: const [
              AppSegment(
                value: MedicineCabinetScope.personal,
                label: '个人药箱',
              ),
              AppSegment(
                value: MedicineCabinetScope.family,
                label: '家庭药箱',
              ),
            ],
            onChanged: (scope) {
              if (scope == _scope) return;
              setState(() => _scope = scope);
              _load(clearCollection: true);
            },
          ),
        ),
        if (collection != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              key: const Key('medicine-search'),
              controller: _searchController,
              onChanged: _setQuery,
              decoration: InputDecoration(
                hintText: '搜索药品或规格',
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: _clearQuery,
                        icon: const Icon(LucideIcons.x, size: 20),
                      ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AppSegmentedControl<_ExpiryFilter>(
              key: const ValueKey('cabinet-filter-tabs'),
              value: _filter,
              options: _filterOptions(collection),
              onChanged: _setFilter,
            ),
          ),
        ],
        Expanded(
          child: CustomScrollView(
            key: const PageStorageKey('cabinet-list-scroll'),
            slivers: _listSlivers(context, expanded),
          ),
        ),
      ],
    );
  }

  List<AppSegment<_ExpiryFilter>> _filterOptions(
    MedicineCollection collection,
  ) {
    final queryMatches = _filterByQuery(
      collection.items,
      _query.trim().toLowerCase(),
    ).toList();
    final counts = <_ExpiryFilter, int>{
      _ExpiryFilter.all: queryMatches.length,
      _ExpiryFilter.expiring: queryMatches
          .where((item) => item.status == MedicineStatus.expiring)
          .length,
      _ExpiryFilter.expired: queryMatches
          .where((item) => item.status == MedicineStatus.expired)
          .length,
    };
    return <AppSegment<_ExpiryFilter>>[
      AppSegment(
        value: _ExpiryFilter.all,
        label: '全部',
        count: counts[_ExpiryFilter.all],
      ),
      AppSegment(
        value: _ExpiryFilter.expiring,
        label: '临期',
        count: counts[_ExpiryFilter.expiring],
      ),
      AppSegment(
        value: _ExpiryFilter.expired,
        label: '已过期',
        count: counts[_ExpiryFilter.expired],
      ),
    ];
  }

  List<Widget> _listSlivers(BuildContext context, bool expanded) {
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
        if (_scope == MedicineCabinetScope.family &&
            _error is MedicineCabinetApiException &&
            (_error as MedicineCabinetApiException).statusCode == 400) {
          return [
            ...permissionRecovery,
            ..._stateSlivers(AppContentState.empty(
              title: '尚未加入家庭',
              message: '创建家庭或使用邀请码加入后，即可共享药品库存',
              actionLabel: '前往设置',
              onAction: widget.onOpenSettings,
            )),
          ];
        }
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
    final slivers = <Widget>[
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
      final isUnfilteredEmpty = collection.items.isEmpty &&
          _query.trim().isEmpty &&
          _filter == _ExpiryFilter.all;
      if (isUnfilteredEmpty) {
        slivers.addAll(
          _stateSlivers(
            _MedicineCabinetEmptyState(
              entryEnabled: !_isOpeningEntry &&
                  (widget.onCapture != null || widget.onCreateBatch != null),
              onCreate: _openEntrySheet,
            ),
          ),
        );
        return slivers;
      }
      slivers.addAll(_stateSlivers(const AppContentState.empty(
        title: '没有符合条件的药品',
        message: '调整搜索或有效期筛选后再查看',
      )));
      return slivers;
    }
    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        sliver: DecoratedSliver(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context)
                    .colorScheme
                    .shadow
                    .withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          sliver: SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) => _MedicineRow(
              medicine: visible[index],
              position: _listRowPosition(index, visible.length),
              onTap: () => _openMedicine(visible[index], expanded),
            ),
          ),
        ),
      ),
    );
    return slivers;
  }

  List<Widget> _stateSlivers(Widget state) => <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverToBoxAdapter(child: state),
        ),
      ];

  static AppListRowPosition _listRowPosition(int index, int length) {
    if (length == 1) return AppListRowPosition.single;
    if (index == 0) return AppListRowPosition.first;
    if (index == length - 1) return AppListRowPosition.last;
    return AppListRowPosition.middle;
  }

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
    this.manufacturer = '',
    this.photoBytes,
    this.batchNumber = '',
    this.productionDate,
    this.expiryDate,
    this.packageUnit = '',
    this.unitsPerPackage,
    this.unitName = '',
    this.looseUnits = 0,
    this.scope = MedicineCabinetScope.personal,
  });

  final String medicineName;
  final String specification;
  final String manufacturer;
  final List<int>? photoBytes;
  final String batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final int quantity;
  final String packageUnit;
  final double? unitsPerPackage;
  final String unitName;
  final double looseUnits;
  final MedicineCabinetScope scope;
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
    this.scope = MedicineCabinetScope.personal,
    this.voiceInputController,
    this.onCapture,
    this.onCreate,
    this.onCapturePhoto,
    this.onParseDescription,
    this.onCancel,
    super.key,
  });

  final bool canCapture;
  final bool isCapturing;
  final bool canCreateBatch;
  final MedicineCabinetScope scope;
  final VoiceInputController? voiceInputController;
  final Future<void> Function()? onCapture;
  final Future<bool> Function(MedicineBatchInput input)? onCreate;
  final Future<List<int>?> Function()? onCapturePhoto;
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
  final _manufacturerController = TextEditingController();
  final _batchNumberController = TextEditingController();
  final _productionDateController = TextEditingController();
  final _expiryDateController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _packageUnitController = TextEditingController(text: '盒');
  final _unitsPerPackageController = TextEditingController();
  final _unitNameController = TextEditingController(text: '片');
  final _looseUnitsController = TextEditingController(text: '0');
  bool _tracksPreciseInventory = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isVoiceActionInFlight = false;
  String? _error;
  String? _voiceActionError;
  String? _parseError;
  String? _lastParsedDescription;
  List<String> _ambiguities = const [];
  List<int>? _photoBytes;
  bool _isTakingPhoto = false;

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
    _manufacturerController.dispose();
    _batchNumberController.dispose();
    _productionDateController.dispose();
    _expiryDateController.dispose();
    _quantityController.dispose();
    _packageUnitController.dispose();
    _unitsPerPackageController.dispose();
    _unitNameController.dispose();
    _looseUnitsController.dispose();
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

  Future<bool> _parseDescription() async {
    final parse = widget.onParseDescription;
    final text = _descriptionController.text.trim();
    if (parse == null || _isParsing || text.isEmpty) {
      if (text.isEmpty) setState(() => _parseError = '请先输入或说出药品描述');
      return false;
    }
    setState(() {
      _isParsing = true;
      _parseError = null;
      _ambiguities = const [];
    });
    try {
      final draft = await parse(text);
      if (!mounted || _descriptionController.text.trim() != text) return false;
      if (draft.medicineName != null) {
        _nameController.text = draft.medicineName!;
      }
      if (draft.specification != null) {
        _specificationController.text = draft.specification!;
      }
      if (draft.manufacturer != null) {
        _manufacturerController.text = draft.manufacturer!;
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
      final hasPreciseInventory = draft.packageUnit != null &&
          draft.unitsPerPackage != null &&
          draft.unitName != null;
      if (hasPreciseInventory) {
        _packageUnitController.text = draft.packageUnit!;
        _unitsPerPackageController.text =
            _formatInventoryInput(draft.unitsPerPackage!);
        _unitNameController.text = draft.unitName!;
        _looseUnitsController.text =
            _formatInventoryInput(draft.looseUnits ?? 0);
      }
      setState(() {
        if (hasPreciseInventory) _tracksPreciseInventory = true;
        _lastParsedDescription = text;
        _ambiguities = draft.ambiguities;
        _error = null;
      });
      return true;
    } catch (_) {
      if (mounted && _descriptionController.text.trim() == text) {
        setState(() => _parseError = '智能解析失败，请稍后重试');
      }
      return false;
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  Future<void> _submitDescription() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _parseDescription();
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
        await _submitDescription();
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

  Widget _buildDescriptionActions(
    BuildContext context,
    VoiceInputPhase phase,
  ) {
    final description = _descriptionController.text.trim();
    final isCurrentDescriptionParsed = description.isNotEmpty &&
        description == _lastParsedDescription &&
        _parseError == null;
    final canUseVoice = !_isSaving &&
        !_isParsing &&
        !_isVoiceActionInFlight &&
        phase != VoiceInputPhase.transcribing &&
        phase != VoiceInputPhase.failure;

    late final String stage;
    late final Widget action;
    if (_isParsing) {
      stage = 'parsing';
      action = const _DescriptionProgress(label: '正在理解并填写…');
    } else if (phase == VoiceInputPhase.transcribing) {
      stage = 'transcribing';
      action = const _DescriptionProgress(label: '正在转写…');
    } else if (phase == VoiceInputPhase.recording) {
      stage = 'recording';
      action = OutlinedButton.icon(
        key: const Key('medicine-entry-voice'),
        onPressed: canUseVoice ? _handleVoiceAction : null,
        icon: const Icon(LucideIcons.square),
        label: Text('停止录音 ${_formatDuration(_voice!.elapsed)}'),
      );
    } else if (isCurrentDescriptionParsed) {
      stage = 'parsed';
      action = Row(
        children: [
          const Expanded(child: _DescriptionParsedStatus()),
          IconButton(
            key: const Key('medicine-entry-voice'),
            tooltip: '重新语音输入',
            onPressed: canUseVoice ? _handleVoiceAction : null,
            icon: const Icon(LucideIcons.mic),
          ),
        ],
      );
    } else if (_isVoiceActionInFlight) {
      stage = 'preparing-voice';
      action = const _DescriptionProgress(label: '正在准备语音…');
    } else if (description.isNotEmpty) {
      stage = 'text-ready';
      action = Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('medicine-entry-parse'),
              onPressed: widget.onParseDescription != null && !_isSaving
                  ? _submitDescription
                  : null,
              icon: const Icon(LucideIcons.sparkles),
              label: const Text('解析'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('medicine-entry-voice'),
            onPressed: canUseVoice ? _handleVoiceAction : null,
            icon: const Icon(LucideIcons.mic),
            label: const Text('语音'),
          ),
        ],
      );
    } else {
      stage = 'voice-ready';
      action = OutlinedButton.icon(
        key: const Key('medicine-entry-voice'),
        onPressed: canUseVoice ? _handleVoiceAction : null,
        icon: const Icon(LucideIcons.mic),
        label: const Text('语音描述'),
      );
    }

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(key: ValueKey(stage), child: action),
      ),
    );
  }

  Future<void> _save() async {
    final onCreate = widget.onCreate;
    if (onCreate == null || _isSaving || _isParsing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final description = _descriptionController.text.trim();
    if (_nameController.text.trim().isEmpty &&
        description.isNotEmpty &&
        description != _lastParsedDescription &&
        widget.onParseDescription != null) {
      final parsed = await _parseDescription();
      if (!parsed || !mounted) return;
      setState(() {
        _error = _ambiguities.isEmpty
            ? '智能解析已完成，请核对后再次点击保存'
            : '请先核对上方提示，确认无误后再次点击保存';
      });
      return;
    }
    final quantity = int.tryParse(_quantityController.text.trim());
    final unitsPerPackage = _tracksPreciseInventory
        ? double.tryParse(_unitsPerPackageController.text.trim())
        : null;
    final looseUnits = _tracksPreciseInventory
        ? double.tryParse(_looseUnitsController.text.trim())
        : 0.0;
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
    if (_tracksPreciseInventory &&
        (_packageUnitController.text.trim().isEmpty ||
            unitsPerPackage == null ||
            unitsPerPackage <= 0 ||
            _unitNameController.text.trim().isEmpty)) {
      setState(() => _error = '请完整填写包装单位、每包装含量和计量单位');
      return;
    }
    if (_tracksPreciseInventory &&
        (looseUnits == null ||
            looseUnits < 0 ||
            looseUnits >= unitsPerPackage!)) {
      setState(() => _error = '已开封剩余量需要大于等于 0，且小于每包装含量');
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
        manufacturer: _manufacturerController.text.trim(),
        photoBytes: _photoBytes,
        batchNumber: _batchNumberController.text.trim(),
        productionDate: productionDate,
        expiryDate: expiryDate,
        quantity: quantity,
        packageUnit:
            _tracksPreciseInventory ? _packageUnitController.text.trim() : '',
        unitsPerPackage: unitsPerPackage,
        unitName:
            _tracksPreciseInventory ? _unitNameController.text.trim() : '',
        looseUnits: looseUnits ?? 0,
        scope: widget.scope,
      ));
      if (!mounted) return;
      if (!created) {
        setState(() => _error = '保存失败，请检查网络后重试');
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _takePhoto() async {
    final capture = widget.onCapturePhoto;
    if (capture == null || _isTakingPhoto) return;
    setState(() => _isTakingPhoto = true);
    try {
      final bytes = await capture();
      if (mounted && bytes != null) setState(() => _photoBytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = '拍照失败，请检查相机权限后重试');
    } finally {
      if (mounted) setState(() => _isTakingPhoto = false);
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
    final theme = Theme.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Material(
          key: const Key('medicine-entry-sheet'),
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '录入药品',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      SizedBox(
                        height: 44,
                        child: TextButton(
                          onPressed: _isSaving ? null : _cancel,
                          child: const Text('取消'),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  color: theme.colorScheme.outlineVariant,
                  height: 0.5,
                  thickness: 0.5,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _EntrySection(
                          title: '快速识别',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                key: const Key('medicine-entry-capture'),
                                onPressed:
                                    widget.canCapture && !widget.isCapturing
                                        ? widget.onCapture
                                        : null,
                                icon: const Icon(LucideIcons.camera),
                                label: const Text('拍照识别药盒'),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _EntryField(
                                label: '文字或语音描述',
                                child: TextField(
                                  key: const Key('medicine-entry-description'),
                                  controller: _descriptionController,
                                  minLines: 3,
                                  maxLines: 5,
                                  maxLength: 300,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) {
                                    unawaited(_submitDescription());
                                  },
                                  onChanged: (_) {
                                    setState(() {
                                      _error = null;
                                      _parseError = null;
                                    });
                                  },
                                  decoration: const InputDecoration(
                                    hintText: '例如：依巴斯汀 20片，1盒，下个月底到期',
                                  ),
                                ),
                              ),
                              _buildDescriptionActions(context, phase),
                              if (_parseError != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                _InlineMessage(
                                  text: _parseError!,
                                  isError: true,
                                ),
                              ],
                              if (_ambiguities.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.sm),
                                _InlineMessage(
                                  text: '请核对：${_ambiguities.join('；')}',
                                ),
                              ],
                              _VoiceStatus(
                                voice: _voice,
                                phase: phase,
                                actionError: _voiceActionError,
                                onRetry: _retryVoice,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        _EntrySection(
                          title: '药品信息',
                          child: Column(
                            children: [
                              _EntryField(
                                label: '药品名称',
                                required: true,
                                child: TextField(
                                  key: const Key('medicine-entry-name'),
                                  controller: _nameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                      hintText: '例如：依巴斯汀'),
                                ),
                              ),
                              _EntryField(
                                label: '规格',
                                child: TextField(
                                  key:
                                      const Key('medicine-entry-specification'),
                                  controller: _specificationController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                      hintText: '例如：20片/盒'),
                                ),
                              ),
                              _EntryField(
                                label: '生产公司',
                                optional: true,
                                child: TextField(
                                  key: const Key('medicine-entry-manufacturer'),
                                  controller: _manufacturerController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                      hintText: '药盒上的生产企业'),
                                ),
                              ),
                              _EntryPhoto(
                                photoBytes: _photoBytes,
                                takingPhoto: _isTakingPhoto,
                                enabled: widget.onCapturePhoto != null,
                                onTakePhoto: _takePhoto,
                                onRemove: () =>
                                    setState(() => _photoBytes = null),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        _EntrySection(
                          title: '库存与有效期',
                          child: Column(
                            children: [
                              _EntryField(
                                label: '有效期',
                                child: TextField(
                                  key: const Key('medicine-entry-expiry-date'),
                                  controller: _expiryDateController,
                                  keyboardType: TextInputType.datetime,
                                  decoration: const InputDecoration(
                                    hintText: 'YYYY-MM-DD',
                                    suffixIcon: Icon(LucideIcons.calendarDays),
                                  ),
                                ),
                              ),
                              _EntryField(
                                label: '生产日期',
                                optional: true,
                                child: TextField(
                                  key: const Key(
                                    'medicine-entry-production-date',
                                  ),
                                  controller: _productionDateController,
                                  keyboardType: TextInputType.datetime,
                                  decoration: const InputDecoration(
                                    hintText: 'YYYY-MM-DD',
                                    suffixIcon: Icon(LucideIcons.calendarDays),
                                  ),
                                ),
                              ),
                              _EntryField(
                                label: '包装数量',
                                required: true,
                                child: TextField(
                                  key: const Key('medicine-entry-quantity'),
                                  controller: _quantityController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    hintText: '例如：2（盒、瓶或袋）',
                                  ),
                                ),
                              ),
                              SwitchListTile.adaptive(
                                key: const Key('medicine-entry-precise-toggle'),
                                contentPadding: EdgeInsets.zero,
                                minVerticalPadding: AppSpacing.sm,
                                title: const Text('精确剩余量'),
                                subtitle: const Text('每包装含量与已开封余量'),
                                value: _tracksPreciseInventory,
                                onChanged: (value) => setState(
                                  () => _tracksPreciseInventory = value,
                                ),
                              ),
                              if (_tracksPreciseInventory) ...[
                                _EntryField(
                                  label: '包装单位',
                                  required: true,
                                  child: TextField(
                                    key: const Key(
                                        'medicine-entry-package-unit'),
                                    controller: _packageUnitController,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: '例如：盒、瓶或袋',
                                    ),
                                  ),
                                ),
                                _EntryField(
                                  label: '每包装含量',
                                  required: true,
                                  child: TextField(
                                    key: const Key(
                                        'medicine-entry-units-per-package'),
                                    controller: _unitsPerPackageController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: '例如：7',
                                    ),
                                  ),
                                ),
                                _EntryField(
                                  label: '计量单位',
                                  required: true,
                                  child: TextField(
                                    key: const Key('medicine-entry-unit-name'),
                                    controller: _unitNameController,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: '例如：片、粒或毫升',
                                    ),
                                  ),
                                ),
                                _EntryField(
                                  label: '已开封剩余量',
                                  optional: true,
                                  child: TextField(
                                    key:
                                        const Key('medicine-entry-loose-units'),
                                    controller: _looseUnitsController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '未开封请填 0',
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Material(
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          _InlineMessage(text: _error!, isError: true),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        FilledButton(
                          key: const Key('medicine-entry-save'),
                          onPressed:
                              widget.canCreateBatch && !_isSaving && !_isParsing
                                  ? _save
                                  : null,
                          child: _isSaving || _isParsing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('保存到药箱'),
                        ),
                      ],
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

String _formatInventoryInput(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

class _EntrySection extends StatelessWidget {
  const _EntrySection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      );
}

class _EntryField extends StatelessWidget {
  const _EntryField({
    required this.label,
    required this.child,
    this.required = false,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suffix = required
        ? ' *'
        : optional
            ? '（选填）'
            : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$label$suffix',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _EntryPhoto extends StatelessWidget {
  const _EntryPhoto({
    required this.photoBytes,
    required this.takingPhoto,
    required this.enabled,
    required this.onTakePhoto,
    required this.onRemove,
  });

  final List<int>? photoBytes;
  final bool takingPhoto;
  final bool enabled;
  final VoidCallback onTakePhoto;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bytes = photoBytes;
    if (bytes != null) {
      return Semantics(
        label: '已添加药品照片',
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child:
                    Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: '重新拍摄',
                    onPressed: takingPhoto ? null : onTakePhoto,
                    icon: const Icon(LucideIcons.camera),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filledTonal(
                    tooltip: '移除照片',
                    onPressed: onRemove,
                    icon: const Icon(LucideIcons.trash2),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return ListTile(
      key: const Key('medicine-entry-photo'),
      contentPadding: EdgeInsets.zero,
      tileColor: Colors.transparent,
      leading: const Icon(LucideIcons.camera),
      title: const Text('药品照片'),
      subtitle: Text(takingPhoto ? '正在打开相机' : '选填，方便以后购买同款'),
      trailing: const Icon(LucideIcons.chevronRight, size: 20),
      enabled: enabled && !takingPhoto,
      onTap: enabled && !takingPhoto ? onTakePhoto : null,
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? LucideIcons.circleAlert : LucideIcons.info,
            size: 18,
            color: isError
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DescriptionProgress extends StatelessWidget {
  const _DescriptionProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

class _DescriptionParsedStatus extends StatelessWidget {
  const _DescriptionParsedStatus();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: '已解析，请核对下方药品信息',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(
              LucideIcons.circleCheck,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '已解析，请核对',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceStatus extends StatelessWidget {
  const _VoiceStatus({
    required this.voice,
    required this.phase,
    required this.actionError,
    required this.onRetry,
  });

  final VoiceInputController? voice;
  final VoiceInputPhase phase;
  final String? actionError;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
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
    return const SizedBox.shrink();
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

class _MedicineCabinetEmptyState extends StatelessWidget {
  const _MedicineCabinetEmptyState({
    required this.entryEnabled,
    required this.onCreate,
  });

  final bool entryEnabled;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '药箱还是空的。录入第一款药品后，可以集中查看库存和有效期。',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ExcludeSemantics(child: _MedicineCabinetIllustration()),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '药箱还是空的',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '录入药品后，可以集中查看库存和有效期',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  key: const ValueKey('medicine-empty-create-action'),
                  onPressed: entryEnabled ? onCreate : null,
                  icon: const Icon(LucideIcons.plus),
                  label: const Text('录入第一款药品'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedicineCabinetIllustration extends StatelessWidget {
  const _MedicineCabinetIllustration();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      key: const ValueKey('medicine-cabinet-empty-illustration'),
      width: 190,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 4,
            child: Container(
              width: 156,
              height: 22,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 13,
            child: Transform.rotate(
              angle: -0.05,
              child: Container(
                width: 142,
                height: 122,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7E8D1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(
                    color: const Color(0xFFE6CDAA),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A6D4D30),
                      blurRadius: 14,
                      offset: Offset(7, 9),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 34,
            top: 20,
            child: Container(
              width: 128,
              height: 108,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCF6),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 50,
                    child: Container(height: 3, color: const Color(0xFFE6CDAA)),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Container(height: 3, color: const Color(0xFFE6CDAA)),
                  ),
                  Positioned(
                    left: 18,
                    top: 15,
                    child: _IllustrationBottle(
                      body: const Color(0xFF9AD3BE),
                      cap: primary,
                    ),
                  ),
                  const Positioned(
                    right: 20,
                    top: 24,
                    child: _IllustrationBox(color: Color(0xFFF1AE85)),
                  ),
                  const Positioned(
                    left: 18,
                    bottom: 13,
                    child: _IllustrationBox(color: Color(0xFFF3CB70)),
                  ),
                  Positioned(
                    right: 19,
                    bottom: 14,
                    child: Transform.rotate(
                      angle: -0.45,
                      child: Container(
                        width: 29,
                        height: 13,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3A4A1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFD77F7C)),
                        ),
                        child: Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 1,
                            color: const Color(0xFFD77F7C),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 4,
            child: Icon(LucideIcons.sparkles, size: 22, color: primary),
          ),
        ],
      ),
    );
  }
}

class _IllustrationBottle extends StatelessWidget {
  const _IllustrationBottle({required this.body, required this.cap});

  final Color body;
  final Color cap;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            width: 21,
            height: 7,
            decoration: BoxDecoration(
              color: cap,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusSm),
              ),
            ),
          ),
          Container(
            width: 26,
            height: 27,
            decoration: BoxDecoration(
              color: body,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
          ),
        ],
      );
}

class _IllustrationBox extends StatelessWidget {
  const _IllustrationBox({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.xs),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(2, 3),
            ),
          ],
        ),
      );
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
      MedicineStatus.active => Theme.of(context).colorScheme.onSurfaceVariant,
      MedicineStatus.expiring => semantic.warning,
      MedicineStatus.expired => Theme.of(context).colorScheme.error,
      MedicineStatus.unknown => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final status = medicineStatusLabel(medicine.status);
    final subtitle = [
      if (medicine.specification.trim().isNotEmpty) medicine.specification,
      medicine.inventoryLabel,
      _formatExpiry(medicine.nearestExpiry),
    ].join(' · ');

    return AppListRow(
      key: ValueKey('medicine-row-${medicine.id}'),
      icon: LucideIcons.pill,
      title: medicine.name,
      subtitle: subtitle,
      statusText: status,
      statusColor: color,
      position: position,
      onTap: onTap,
    );
  }
}

enum _ExpiryFilter { all, expiring, expired }

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
