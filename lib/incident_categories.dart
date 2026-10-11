import 'package:flutter/material.dart';

class IncidentCategory {
  final String id;
  final String label;
  final IconData icon;
  final String emoji;

  const IncidentCategory(this.id, this.label, this.icon, this.emoji);
}

const incidentCategories = [
  IncidentCategory('fence', 'Broken fence', Icons.fence, '🧱'),
  IncidentCategory(
      'light', 'Street light broken', Icons.lightbulb_outline, '💡'),
  IncidentCategory('nfc', 'NFC tag not working', Icons.nfc, '📡'),
  IncidentCategory('grass', 'Long grass', Icons.grass, '🌿'),
  IncidentCategory('other', 'Other', Icons.more_horiz, '⚠️'),
];

IncidentCategory categoryById(String id) => incidentCategories
    .firstWhere((c) => c.id == id, orElse: () => incidentCategories.last);
