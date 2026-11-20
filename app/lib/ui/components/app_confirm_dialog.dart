import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smart_reminder_app/app/theme/app_spacing.dart';

/// 全局通用的友好二次确认对话框
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required IconData icon,
  required Color iconColor,
  Color? iconBackgroundColor,
  required String title,
  required String primaryText,
  String? secondaryText,
  String? infoBannerText,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  Color confirmColor = const Color(0xFF059669),
  bool isDestructive = false,
}) async {
  final bg = iconBackgroundColor ?? iconColor.withValues(alpha: 0.12);
  final effectiveConfirmColor = isDestructive
      ? Theme.of(context).colorScheme.error
      : confirmColor;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Center(
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              primaryText,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (secondaryText != null && secondaryText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                secondaryText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (infoBannerText != null && infoBannerText.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      LucideIcons.info,
                      size: 16,
                      color: iconColor,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        infoBannerText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            child: Text(cancelLabel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: effectiveConfirmColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              elevation: 0,
            ),
            icon: Icon(
              isDestructive ? LucideIcons.trash2 : LucideIcons.check,
              size: 16,
            ),
            label: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    },
  );

  return confirmed == true;
}

/// 专用于服药打卡的二次确认弹窗
Future<bool> showMedicationConfirmDialog({
  required BuildContext context,
  required String medicineTitle,
  String? doseLabel,
  bool isAdvance = false,
}) {
  return showAppConfirmDialog(
    context: context,
    icon: LucideIcons.pill,
    iconColor: const Color(0xFF059669),
    iconBackgroundColor: const Color(0xFFECFDF5),
    title: isAdvance ? '确认提前服药' : '确认服药打卡',
    primaryText: medicineTitle,
    secondaryText: doseLabel != null && doseLabel.isNotEmpty
        ? '计划剂量：$doseLabel'
        : null,
    infoBannerText: isAdvance
        ? '将精确记录当前时间为实际提前服药时间，并自动扣减库存 1 次。'
        : '将精确记录当前时间为实际服药时间，并自动扣减库存 1 次。',
    confirmLabel: isAdvance ? '确认提前服药' : '确认服药',
    cancelLabel: '稍后再说',
    confirmColor: const Color(0xFF059669),
  );
}
