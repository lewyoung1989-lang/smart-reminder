import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../platform/notifications/reminder_notification_scheduler.dart';
import '../data/reminder_api.dart';
import '../domain/reminder.dart';

typedef ListReminders = Future<ReminderPage> Function({
  required ReminderStatus status,
  Uri? pageUrl,
});

class ReminderHomeScreen extends StatefulWidget {
  const ReminderHomeScreen({
    required this.listReminders,
    required this.cancelReminder,
    required this.createReminder,
    this.notificationScheduler,
    super.key,
  });

  final ListReminders listReminders;
  final Future<Reminder> Function(String id) cancelReminder;
  final WidgetBuilder createReminder;
  final ReminderNotificationScheduler? notificationScheduler;

  @override
  State<ReminderHomeScreen> createState() => _ReminderHomeScreenState();
}

class _ReminderHomeScreenState extends State<ReminderHomeScreen>
    with SingleTickerProviderStateMixin {
  static const _statuses = [
    ReminderStatus.pending,
    ReminderStatus.expired,
    ReminderStatus.cancelled,
  ];

  late final TabController _tabs;
  late final Map<ReminderStatus, ScrollController> _scrollControllers;
  final _states = {
    for (final status in _statuses) status: _ReminderTabState(),
  };
  final _cancelling = <String>{};
  int _observedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _statuses.length, vsync: this)
      ..addListener(_handleTabChange);
    _scrollControllers = {
      for (final status in _statuses)
        status: ScrollController()..addListener(() => _handleScroll(status)),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFirst(ReminderStatus.pending);
    });
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_handleTabChange)
      ..dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabs.index == _observedTabIndex) return;
    _observedTabIndex = _tabs.index;
    _ensureLoaded(_statuses[_tabs.index]);
  }

  void _handleScroll(ReminderStatus status) {
    final controller = _scrollControllers[status]!;
    if (controller.hasClients && controller.position.extentAfter < 200) {
      _loadNext(status);
    }
  }

  void _ensureLoaded(ReminderStatus status) {
    final state = _states[status]!;
    if (!state.hasLoaded && !state.loading) {
      _loadFirst(status);
    }
  }

  void _invalidate(ReminderStatus status) {
    final state = _states[status]!;
    state
      ..generation += 1
      ..hasLoaded = false
      ..loading = false
      ..loadingMore = false
      ..firstPageFailed = false
      ..loadMoreFailed = false;
  }

  void _removePending(String reminderId) {
    final pendingState = _states[ReminderStatus.pending]!;
    setState(() {
      pendingState.items = pendingState.items
          .where((item) => item.id != reminderId)
          .toList(growable: false);
    });
  }

  Future<void> _loadFirst(ReminderStatus status) async {
    final state = _states[status]!;
    final generation = ++state.generation;
    setState(() {
      state.hasLoaded = true;
      state.loading = true;
      state.loadingMore = false;
      state.firstPageFailed = false;
      state.loadMoreFailed = false;
    });
    try {
      final page = await widget.listReminders(status: status);
      if (!mounted || generation != state.generation) return;
      setState(() {
        state.items = page.reminders;
        state.nextPage = page.nextPage;
        state.loading = false;
      });
    } catch (_) {
      if (!mounted || generation != state.generation) return;
      setState(() {
        state.loading = false;
        state.firstPageFailed = true;
      });
    }
  }

  Future<void> _loadNext(ReminderStatus status) async {
    final state = _states[status]!;
    final next = state.nextPage;
    if (next == null || state.loadingMore || state.loading) return;
    final generation = state.generation;
    setState(() {
      state.loadingMore = true;
      state.loadMoreFailed = false;
    });
    try {
      final page = await widget.listReminders(status: status, pageUrl: next);
      if (!mounted || generation != state.generation) return;
      setState(() {
        state.items = [...state.items, ...page.reminders];
        state.nextPage = page.nextPage;
        state.loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != state.generation) return;
      setState(() {
        state.loadingMore = false;
        state.loadMoreFailed = true;
      });
    }
  }

  Future<void> _createReminder() async {
    final result = await Navigator.of(context).push<ReminderCreationResult>(
      MaterialPageRoute(builder: widget.createReminder),
    );
    if (!mounted || result == null) return;
    _tabs.animateTo(0);
    await _loadFirst(ReminderStatus.pending);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.notificationScheduled ? '提醒已创建，通知已安排' : '提醒已创建，但手机通知未安排',
        ),
      ),
    );
  }

  Future<void> _askToCancel(Reminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('取消“${reminder.title}”？'),
        content: const Text('取消后不会再通知'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留提醒'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _cancel(reminder);
    }
  }

  Future<void> _cancel(Reminder reminder) async {
    if (_cancelling.contains(reminder.id)) return;
    setState(() => _cancelling.add(reminder.id));
    try {
      await widget.cancelReminder(reminder.id);
    } on ReminderApiException catch (error) {
      if (error.statusCode == 409 && error.code == 'reminder_expired') {
        if (!mounted) return;
        _removePending(reminder.id);
        _invalidate(ReminderStatus.expired);
        await _loadFirst(ReminderStatus.pending);
        if (!mounted) return;
        setState(() => _cancelling.remove(reminder.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提醒时间已过，不能取消')),
        );
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('取消失败，请检查网络后重试')),
        );
        setState(() => _cancelling.remove(reminder.id));
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('取消失败，请检查网络后重试')),
        );
        setState(() => _cancelling.remove(reminder.id));
      }
      return;
    }

    if (mounted) {
      _removePending(reminder.id);
    }

    var localCancellationFailed = false;
    try {
      await widget.notificationScheduler?.cancel(reminderId: reminder.id);
    } catch (_) {
      localCancellationFailed = true;
    }

    _invalidate(ReminderStatus.cancelled);
    await _loadFirst(ReminderStatus.pending);
    if (!mounted) return;
    setState(() => _cancelling.remove(reminder.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localCancellationFailed ? '提醒已取消，但手机通知可能仍存在' : '提醒已取消',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('提醒'),
          actions: [
            IconButton(
              key: const Key('add-reminder'),
              tooltip: '创建提醒',
              onPressed: _createReminder,
              icon: const Icon(LucideIcons.plus),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: '待提醒'),
              Tab(text: '已过期'),
              Tab(text: '已取消'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            for (final status in _statuses) _buildTab(status),
          ],
        ),
      );

  Widget _buildTab(ReminderStatus status) {
    final state = _states[status]!;
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.firstPageFailed && state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.cloudOff, size: 40),
            const SizedBox(height: 12),
            const Text('提醒加载失败'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _loadFirst(status),
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFirst(status),
      child: ListView.separated(
        key: Key('reminder-list-${status.apiValue}'),
        controller: _scrollControllers[status],
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: state.items.isEmpty ? 1 : state.items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (state.items.isEmpty) {
            return SizedBox(
              height: 280,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_emptyIcon(status), size: 44),
                    const SizedBox(height: 12),
                    Text(_emptyText(status)),
                  ],
                ),
              ),
            );
          }
          if (index == state.items.length) {
            return SizedBox(
              height: 64,
              child: state.loadMoreFailed
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('更多提醒加载失败'),
                        TextButton.icon(
                          onPressed: () => _loadNext(status),
                          icon: const Icon(LucideIcons.refreshCw),
                          label: const Text('重试加载'),
                        ),
                      ],
                    )
                  : state.loadingMore
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
            );
          }
          return _ReminderRow(
            reminder: state.items[index],
            cancelling: _cancelling.contains(state.items[index].id),
            onCancel: status == ReminderStatus.pending
                ? () => _askToCancel(state.items[index])
                : null,
          );
        },
      ),
    );
  }

  static IconData _emptyIcon(ReminderStatus status) => switch (status) {
        ReminderStatus.pending => LucideIcons.bell,
        ReminderStatus.expired => LucideIcons.history,
        ReminderStatus.cancelled => LucideIcons.bellOff,
        ReminderStatus.completed => LucideIcons.circleCheck,
      };

  static String _emptyText(ReminderStatus status) => switch (status) {
        ReminderStatus.pending => '暂无待提醒事项',
        ReminderStatus.expired => '暂无已过期提醒',
        ReminderStatus.cancelled => '暂无已取消提醒',
        ReminderStatus.completed => '暂无已完成提醒',
      };
}

class _ReminderTabState {
  List<Reminder> items = [];
  Uri? nextPage;
  bool hasLoaded = false;
  bool loading = false;
  bool loadingMore = false;
  bool firstPageFailed = false;
  bool loadMoreFailed = false;
  int generation = 0;
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.cancelling,
    required this.onCancel,
  });

  final Reminder reminder;
  final bool cancelling;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => ListTile(
        key: Key('reminder-${reminder.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        leading: Icon(
          reminder.severity == ReminderSeverity.alarm
              ? LucideIcons.alarmClock
              : LucideIcons.bell,
          color: _statusColor(reminder.status),
        ),
        title: Text(reminder.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_formatDateTime(reminder.scheduledAt)),
        ),
        trailing: onCancel == null
            ? null
            : cancelling
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    key: Key('cancel-${reminder.id}'),
                    tooltip: '取消提醒',
                    onPressed: onCancel,
                    icon: const Icon(LucideIcons.bellOff),
                  ),
      );

  static String _formatDateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static Color _statusColor(ReminderStatus status) => switch (status) {
        ReminderStatus.pending => const Color(0xFF166B5A),
        ReminderStatus.expired => const Color(0xFF656A70),
        ReminderStatus.cancelled => const Color(0xFF9B4A4A),
        ReminderStatus.completed => const Color(0xFF3F6F57),
      };
}
