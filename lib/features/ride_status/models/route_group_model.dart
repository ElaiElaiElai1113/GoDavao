import 'package:godavao/features/ride_status/models/match_card_model.dart';

/// Model grouping matches by driver route.
class RouteGroup {
  final String routeId;
  final String? routeName;
  int? capacityTotal;
  int? capacityAvailable;
  final List<MatchCard> items;
  final Set<String> selected;

  RouteGroup({
    required this.routeId,
    this.routeName,
    required this.items,
    this.capacityTotal,
    this.capacityAvailable,
    Set<String>? selected,
  }) : selected = selected ?? {};

  /// Get all items with a specific status
  List<MatchCard> byStatus(String status) =>
      items.where((m) => m.status == status).toList();

  /// Get all pending matches
  List<MatchCard> get pending => byStatus('pending');

  /// Get all accepted matches
  List<MatchCard> get accepted => byStatus('accepted');

  /// Get all active rides (en_route)
  List<MatchCard> get active => byStatus('en_route');

  /// Get all completed rides
  List<MatchCard> get completed => byStatus('completed');

  /// Get all failed rides (declined, cancelled)
  List<MatchCard> get failed =>
      items.where((m) => m.isFailed).toList();

  /// Calculate total seats from accepted matches
  int get acceptedSeats =>
      accepted.fold(0, (sum, m) => sum + (m.pax));

  /// Calculate total seats from pending matches that are selected
  int get pendingSeatsSelected =>
      items
          .where((m) => selected.contains(m.matchId) && m.isPending)
          .fold<int>(0, (sum, m) => sum + m.pax);

  /// Calculate total seats used (accepted + selected pending)
  int get totalUsedSeats => acceptedSeats + pendingSeatsSelected;

  /// Calculate available seats
  int get availableSeats =>
      (capacityTotal ?? 0) - totalUsedSeats;

  /// Check if route has capacity for additional seats
  bool hasCapacityFor(int seats) => availableSeats >= seats;

  /// Get total number of items
  int get itemCount => items.length;

  /// Get count of items by status
  Map<String, int> get statusCounts {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    return counts;
  }

  /// Check if any matches are selected
  bool get hasSelection => selected.isNotEmpty;

  /// Clear all selections
  RouteGroup clearSelection() {
    return RouteGroup(
      routeId: routeId,
      routeName: routeName,
      items: items,
      capacityTotal: capacityTotal,
      capacityAvailable: capacityAvailable,
      selected: {},
    );
  }

  /// Toggle selection for a match
  RouteGroup toggleSelection(String matchId) {
    final newSelected = Set<String>.from(selected);
    if (newSelected.contains(matchId)) {
      newSelected.remove(matchId);
    } else {
      newSelected.add(matchId);
    }
    return RouteGroup(
      routeId: routeId,
      routeName: routeName,
      items: items,
      capacityTotal: capacityTotal,
      capacityAvailable: capacityAvailable,
      selected: newSelected,
    );
  }

  /// Add a match to this group
  RouteGroup addMatch(MatchCard match) {
    return RouteGroup(
      routeId: routeId,
      routeName: routeName,
      items: [...items, match],
      capacityTotal: capacityTotal,
      capacityAvailable: capacityAvailable,
      selected: selected,
    );
  }

  /// Remove a match from this group
  RouteGroup removeMatch(String matchId) {
    return RouteGroup(
      routeId: routeId,
      routeName: routeName,
      items: items.where((m) => m.matchId != matchId).toList(),
      capacityTotal: capacityTotal,
      capacityAvailable: capacityAvailable,
      selected: selected..remove(matchId),
    );
  }

  /// Update a match in this group
  RouteGroup updateMatch(MatchCard updatedMatch) {
    return RouteGroup(
      routeId: routeId,
      routeName: routeName,
      items: items.map((m) => m.matchId == updatedMatch.matchId ? updatedMatch : m).toList(),
      capacityTotal: capacityTotal,
      capacityAvailable: capacityAvailable,
      selected: selected,
    );
  }

  /// Update capacity information
  RouteGroup updateCapacity({
    int? total,
    int? available,
  }) {
    return RouteGroup(
      routeId: routeId,
      routeName: routeName,
      items: items,
      capacityTotal: total ?? capacityTotal,
      capacityAvailable: available ?? capacityAvailable,
      selected: selected,
    );
  }

  @override
  String toString() =>
      'RouteGroup(routeId: $routeId, items: ${items.length}, selected: ${selected.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteGroup &&
          runtimeType == other.runtimeType &&
          routeId == other.routeId;

  @override
  int get hashCode => routeId.hashCode;
}

/// Extension for working with lists of RouteGroups
extension RouteGroupListExtension on List<RouteGroup> {
  /// Get all matches across all groups
  List<MatchCard> get allMatches =>
      fold([], (list, group) => [...list, ...group.items]);

  /// Get all pending matches across all groups
  List<MatchCard> get allPending =>
      fold([], (list, group) => [...list, ...group.pending]);

  /// Get all accepted matches across all groups
  List<MatchCard> get allAccepted =>
      fold([], (list, group) => [...list, ...group.accepted]);

  /// Count total items across all groups
  int get totalItems => fold(0, (count, group) => count + group.itemCount);

  /// Count pending items across all groups
  int get totalPending => fold(0, (count, group) => count + group.pending.length);

  /// Count accepted items across all groups
  int get totalAccepted => fold(0, (count, group) => count + group.accepted.length);

  /// Get group by route ID
  RouteGroup? getByRouteId(String routeId) {
    for (final group in this) {
      if (group.routeId == routeId) return group;
    }
    return null;
  }
}
