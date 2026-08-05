import 'package:flutter/material.dart';

import '../domain/inventory_batch.dart';

typedef InventoryBatchLoader = Future<InventoryBatchPage> Function({
  String query,
  Uri? pageUrl,
});
typedef InventoryBatchDeleter = Future<void> Function(String id);

class MedicineCabinetScreen extends StatefulWidget {
  const MedicineCabinetScreen({
    required this.listBatches,
    required this.deleteBatch,
    super.key,
  });

  final InventoryBatchLoader listBatches;
  final InventoryBatchDeleter deleteBatch;

  @override
  State<MedicineCabinetScreen> createState() => _MedicineCabinetScreenState();
}

class _MedicineCabinetScreenState extends State<MedicineCabinetScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  List<InventoryBatch> _batches = const [];
  Uri? _nextPage;
  String _activeQuery = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _failed = false;
  int _requestGeneration = 0;
  final Set<String> _deletedBatchIds = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    _scroll.addListener(_scrollChanged);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _search
      ..removeListener(_searchChanged)
      ..dispose();
    _scroll
      ..removeListener(_scrollChanged)
      ..dispose();
    super.dispose();
  }

  void _searchChanged() => setState(() {});

  void _scrollChanged() {
    if (_scroll.position.extentAfter < 160 && !_loadMoreFailed) {
      _loadNextPage();
    }
  }

  Future<void> _loadFirstPage({String? query}) async {
    final nextQuery = (query ?? _activeQuery).trim();
    final generation = ++_requestGeneration;
    setState(() {
      _activeQuery = nextQuery;
      _loading = true;
      _loadingMore = false;
      _loadMoreFailed = false;
      _failed = false;
    });
    try {
      final page = await widget.listBatches(query: nextQuery);
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _batches = page.batches;
        _deletedBatchIds.clear();
        _nextPage = page.nextPage;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadNextPage() async {
    final pageUrl = _nextPage;
    if (pageUrl == null || _loading || _loadingMore || _failed) {
      return;
    }
    final generation = _requestGeneration;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final page = await widget.listBatches(
        query: _activeQuery,
        pageUrl: pageUrl,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _batches = [
          ..._batches,
          ...page.batches.where(
            (batch) => !_deletedBatchIds.contains(batch.id),
          ),
        ];
        _nextPage = page.nextPage;
        _loadingMore = false;
        _loadMoreFailed = false;
      });
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loadingMore = false;
          _loadMoreFailed = true;
        });
      }
    }
  }

  void _retryNextPage() {
    setState(() => _loadMoreFailed = false);
    _loadNextPage();
  }

  void _submitSearch() => _loadFirstPage(query: _search.text);

  void _clearSearch() {
    _search.clear();
    _loadFirstPage(query: '');
  }

  Future<bool> _confirmDelete(InventoryBatch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这批药品？'),
        content: Text(
          [
            '确定删除“${batch.medicineName}”吗？',
            if (batch.batchNumber.isNotEmpty) '批号 ${batch.batchNumber}',
            '只会删除当前批次，其他批次不受影响。',
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return false;
    }

    try {
      await widget.deleteBatch(batch.id);
      return mounted;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请稍后重试')),
        );
      }
      return false;
    }
  }

  void _removeDeletedBatch(String batchId) {
    setState(() {
      _deletedBatchIds.add(batchId);
      _batches = _batches
          .where((batch) => batch.id != batchId)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('家庭药箱')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                key: const Key('medicine-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                decoration: InputDecoration(
                  hintText: '搜索药品、规格或批号',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_search.text.isNotEmpty)
                        IconButton(
                          tooltip: '清除搜索',
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.clear),
                        ),
                      IconButton(
                        tooltip: '搜索',
                        onPressed: _submitSearch,
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('药箱加载失败'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadFirstPage,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        key: const Key('medicine-cabinet-list'),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _batches.isEmpty ? 1 : _batches.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (_batches.isEmpty) {
            final hasQuery = _activeQuery.isNotEmpty;
            return SizedBox(
              height: 280,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasQuery
                          ? Icons.search_off_outlined
                          : Icons.medication_outlined,
                      size: 44,
                    ),
                    const SizedBox(height: 12),
                    Text(hasQuery ? '没有找到匹配药品' : '药箱里还没有药品'),
                    const SizedBox(height: 4),
                    Text(
                      hasQuery ? '请尝试其他关键词' : '可从“拍照录入”添加药品',
                    ),
                  ],
                ),
              ),
            );
          }
          if (index == _batches.length) {
            return SizedBox(
              height: 64,
              child: _loadMoreFailed
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('更多药品加载失败'),
                        const SizedBox(width: 4),
                        TextButton.icon(
                          onPressed: _retryNextPage,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试加载'),
                        ),
                      ],
                    )
                  : _loadingMore
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
            );
          }
          final batch = _batches[index];
          return Dismissible(
            key: ValueKey('medicine-batch-${batch.id}'),
            direction: DismissDirection.endToStart,
            dismissThresholds: const {
              DismissDirection.endToStart: 0.35,
            },
            background: const _DeleteBackground(),
            confirmDismiss: (_) => _confirmDelete(batch),
            onDismissed: (_) => _removeDeletedBatch(batch.id),
            child: _MedicineBatchRow(batch: batch),
          );
        },
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(height: 2),
            Text(
              '删除',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      );
}

class _MedicineBatchRow extends StatelessWidget {
  const _MedicineBatchRow({required this.batch});

  final InventoryBatch batch;

  @override
  Widget build(BuildContext context) {
    final secondary = [
      if (batch.specification.isNotEmpty) batch.specification,
      if (batch.batchNumber.isNotEmpty) '批号 ${batch.batchNumber}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batch.medicineName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (secondary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(secondary),
                ],
                const SizedBox(height: 6),
                Text(
                  batch.expiryDate == null
                      ? '有效期未录入'
                      : '有效期 ${_formatDate(batch.expiryDate!)}',
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('数量 ${batch.quantity}'),
              const SizedBox(height: 6),
              Chip(
                visualDensity: VisualDensity.compact,
                backgroundColor: _chipBackground(batch.expiryStatus),
                labelStyle: TextStyle(
                  color: _chipForeground(batch.expiryStatus),
                ),
                label: Text(_statusLabel(batch)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _statusLabel(InventoryBatch batch) {
    final days = batch.daysUntilExpiry;
    return switch (batch.expiryStatus) {
      InventoryExpiryStatus.expired =>
        days == null ? '已过期' : '已过期 ${days.abs()} 天',
      InventoryExpiryStatus.expiringSoon => days == 0
          ? '今天过期'
          : days == null
              ? '即将过期'
              : '$days 天后过期',
      InventoryExpiryStatus.valid => '有效',
      InventoryExpiryStatus.unknown => '未录入有效期',
    };
  }

  static Color _chipBackground(InventoryExpiryStatus status) =>
      switch (status) {
        InventoryExpiryStatus.expired => const Color(0xFFFCE8E6),
        InventoryExpiryStatus.expiringSoon => const Color(0xFFFFE9B8),
        InventoryExpiryStatus.valid => const Color(0xFFDDEFE6),
        InventoryExpiryStatus.unknown => const Color(0xFFE7E8EA),
      };

  static Color _chipForeground(InventoryExpiryStatus status) =>
      switch (status) {
        InventoryExpiryStatus.expired => const Color(0xFF9B1C1C),
        InventoryExpiryStatus.expiringSoon => const Color(0xFF6B4B00),
        InventoryExpiryStatus.valid => const Color(0xFF195C45),
        InventoryExpiryStatus.unknown => const Color(0xFF4C4F54),
      };
}
