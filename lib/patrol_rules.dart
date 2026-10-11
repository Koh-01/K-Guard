import 'models.dart';
import 'settings.dart';

/// Patrol-order logic: which checkpoint a guard must visit next.
class PatrolRules {
  /// The next checkpoint [guard] must visit, or null if order isn't enforced / no checkpoints.
  /// [checkpoints] must be in patrol order.
  static Checkpoint? nextFor(String guard, List<Checkpoint> checkpoints) {
    if (!AppSettings.enforceOrder || checkpoints.isEmpty) return null;
    final last = AppSettings.lastOrderedCheckpoint(guard);
    final i = checkpoints.indexWhere((c) => c.id == last);
    // Not started (or last checkpoint deleted) -> first; after the last one -> wrap to a new round.
    return checkpoints[i < 0 ? 0 : (i + 1) % checkpoints.length];
  }

  /// 1-based position of [c] in the round.
  static int positionOf(Checkpoint c, List<Checkpoint> checkpoints) =>
      checkpoints.indexWhere((x) => x.id == c.id) + 1;

  /// Records that [guard] completed [c] (or skipped it via an NFC incident).
  static void complete(String guard, Checkpoint c) =>
      AppSettings.setLastOrderedCheckpoint(guard, c.id!);

  /// Whether [c] is the last checkpoint of the round.
  static bool isLast(Checkpoint c, List<Checkpoint> checkpoints) =>
      checkpoints.isNotEmpty && checkpoints.last.id == c.id;
}
