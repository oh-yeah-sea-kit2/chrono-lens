import 'package:flutter/material.dart';

import '../../../models/era.dart';

class EraSelector extends StatelessWidget {
  const EraSelector({
    super.key,
    required this.selectedEra,
    required this.onEraSelected,
  });

  final Era selectedEra;
  final ValueChanged<Era> onEraSelected;

  static Future<void> show(
    BuildContext context, {
    required Era current,
    required ValueChanged<Era> onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EraSelector(
        selectedEra: current,
        onEraSelected: (era) {
          onSelected(era);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '時代を選択',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...Era.values.map((era) => ListTile(
                leading: era == selectedEra
                    ? const Icon(Icons.check_circle, color: Colors.amber)
                    : const Icon(Icons.radio_button_unchecked, color: Colors.white38),
                title: Text(
                  era.label,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  era.subtitle,
                  style: const TextStyle(color: Colors.white54),
                ),
                onTap: () => onEraSelected(era),
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
