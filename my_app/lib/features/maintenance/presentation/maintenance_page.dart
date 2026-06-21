import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppTheme.brandBlue,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: const Icon(Icons.build_outlined, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Maintenance', style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'This page will mirror the website’s Schedule Maintenance workflow next (task form + technician + status + comparison launch).',
          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
