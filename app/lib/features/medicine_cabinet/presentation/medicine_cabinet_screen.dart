import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
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
                _CaptureButton(
                  enabled: widget.onCapture != null &&
                      !_isCapturing &&
                      (widget.captureAvailability ==
                              MedicineCaptureAvailability.ready ||
                          widget.captureAvailability ==
                              MedicineCaptureAvailability.denied),
                  onPressed: _capture,
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

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final button = TextButton.icon(
      onPressed: enabled ? () => onPressed() : null,
      icon: const Icon(LucideIcons.camera),
      label: const Text('拍照录入'),
    );
    if (enabled) return button;
    return Semantics(
      button: true,
      enabled: false,
      label: '拍照录入，拍照录入服务尚未接入',
      hint: '拍照录入服务尚未接入',
      child: ExcludeSemantics(child: button),
    );
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

extension on List<MedicineSummary> {
  MedicineSummary? get firstOrNull => isEmpty ? null : first;
}
