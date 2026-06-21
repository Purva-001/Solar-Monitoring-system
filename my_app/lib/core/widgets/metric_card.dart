import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.unit,
    this.accent,
  });

  final String title;
  final String value;
  final String? unit;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = accent ?? theme.colorScheme.primary;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B), fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      unit!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569), fontWeight: FontWeight.w800),
                    ),
                  ),
                ]
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: a, borderRadius: const BorderRadius.all(Radius.circular(999))),
            ),
          ],
        ),
      ),
    );
  }
}
