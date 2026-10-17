import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass_container.dart';

/// أيقونة داخل دائرة ملوّنة شفافة.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// عنوان قسم: شريط ملوّن متوهّج + أيقونة + عنوان، وسطر فرعي اختياري
/// ([subtitleSpans] لنص منسّق، أو [subtitleText] لنص عادي).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.subtitleSpans,
    this.subtitleText,
    this.titleStyle = AppText.sectionTitle,
    this.subtitleStyle = AppText.sectionSubtitle,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<InlineSpan>? subtitleSpans;
  final String? subtitleText;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitleSpans != null || subtitleText != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: hasSubtitle ? 34 : 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle),
              if (hasSubtitle) ...[
                const SizedBox(height: 2),
                subtitleSpans != null
                    ? Text.rich(TextSpan(style: subtitleStyle, children: subtitleSpans))
                    : Text(subtitleText!, style: subtitleStyle),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// زر "Retry" الزجاجي.
class RetryButton extends StatelessWidget {
  const RetryButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
      label: const Text('Retry', style: TextStyle(color: Colors.white)),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

/// بطاقة زجاجية في وسط مساحة قابلة للسحب (تعمل مع RefreshIndicator).
class _CenteredGlassCard extends StatelessWidget {
  const _CenteredGlassCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: GlassContainer(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// حالة خطأ بملء الشاشة مع زر إعادة المحاولة.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredGlassCard(
      children: [
        const IconBadge(icon: Icons.error_outline, color: AppAccent.unlinked, size: 48),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center, style: AppText.error),
        const SizedBox(height: 16),
        RetryButton(onPressed: onRetry),
      ],
    );
  }
}

/// حالة "لا توجد عناصر بعد" بملء الشاشة.
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.color, required this.message});
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _CenteredGlassCard(
      children: [
        IconBadge(icon: icon, color: color, size: 48),
        const SizedBox(height: 14),
        Text(
          message,
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// قطعة واحدة في [GlassSegmentedControl].
class GlassSegment<T> {
  const GlassSegment({required this.value, required this.label, this.icon, this.enabled = true});
  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
}

/// مبدّل زجاجي (بنفس شكل مبدّل تبويب الرسائل): بطاقة زجاجية، القطعة
/// المختارة بخلفية بيضاء شفافة ونص أبيض عريض، وغير المختارة بنص باهت.
/// يُستخدم بدل ChoiceChip/SegmentedButton اللذين يأخذان ألوان ثيم Material
/// الفاتح فيصبح النص الأبيض غير مقروء على الخلفية الداكنة.
/// [onSelected] يُستدعى حتى للقطعة المختارة (مثل "Custom" لإعادة فتح المنتقي).
class GlassSegmentedControl<T> extends StatelessWidget {
  const GlassSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  final List<GlassSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 14,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [for (final s in segments) Expanded(child: _segment(s))],
      ),
    );
  }

  Widget _segment(GlassSegment<T> s) {
    final isSelected = s.value == selected;
    final color = !s.enabled ? Colors.white24 : (isSelected ? Colors.white : Colors.white60);
    return Semantics(
      button: true,
      selected: isSelected,
      enabled: s.enabled,
      child: Material(
        color: isSelected ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: s.enabled ? () => onSelected(s.value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (s.icon != null) ...[
                  Icon(s.icon, size: 15, color: color),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    s.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
