/// Represents an action available when an advertisement target is discovered.
///
/// Supported type for Phase 4:
/// - 'view' (opens destination URL)
///
/// Future types may include: 'whatsapp', 'reward', 'purchase', 'save'.
class AdAction {
  final String type;
  final String label;
  final String destination;

  const AdAction({
    required this.type,
    required this.label,
    required this.destination,
  });

  factory AdAction.fromJson(Map<String, dynamic> json) {
    return AdAction(
      type: json['type'] as String? ?? 'view',
      label: json['label'] as String? ?? 'VIEW',
      destination: json['destination'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'label': label,
      'destination': destination,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdAction &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          label == other.label &&
          destination == other.destination;

  @override
  int get hashCode => type.hashCode ^ label.hashCode ^ destination.hashCode;
}
