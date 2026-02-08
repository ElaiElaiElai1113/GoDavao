import 'package:flutter/material.dart';
import 'package:godavao/common/app_colors.dart';

import 'package:godavao/features/ride_status/models/route_group_model.dart';
import 'package:godavao/features/ride_status/models/match_card_model.dart';
import 'package:godavao/features/ride_status/widgets/common/match_list_tile.dart';

/// A section widget displaying a driver route with its matches and actions.
class RouteSection extends StatelessWidget {
  const RouteSection({
    super.key,
    required this.routeGroup,
    this.onToggleSelection,
    this.onSelectAllPending,
    this.onClearSelection,
    this.onAcceptSelected,
    this.onStartRoute,
    this.onCompleteRoute,
    this.onDeclineMatch,
    this.onOpenRide,
    this.onChat,
    this.onViewMap,
    this.onViewAllPickups,
    this.onTapRating,
    this.statusColorBuilder,
  });

  final RouteGroup routeGroup;
  final void Function(String matchId)? onToggleSelection;
  final void Function(String routeId)? onSelectAllPending;
  final void Function(String routeId)? onClearSelection;
  final void Function(RouteGroup)? onAcceptSelected;
  final void Function(RouteGroup)? onStartRoute;
  final void Function(RouteGroup)? onCompleteRoute;
  final void Function(MatchCard)? onDeclineMatch;
  final void Function(MatchCard)? onOpenRide;
  final void Function(MatchCard)? onChat;
  final void Function(RouteGroup)? onViewMap;
  final void Function(RouteGroup)? onViewAllPickups;
  final void Function(MatchCard)? onTapRating;
  final Color? Function(String status)? statusColorBuilder;

  static const _purple = AppColors.purple;
  static const _purpleDark = AppColors.purpleDark;

  List<MatchCard> get _pending => routeGroup.byStatus('pending');
  List<MatchCard> get _accepted => routeGroup.byStatus('accepted');
  List<MatchCard> get _enRoute => routeGroup.byStatus('en_route');

  String get _routeTitle {
    if (routeGroup.routeId == 'unassigned') {
      return 'Unassigned route';
    }
    if (routeGroup.items.isNotEmpty &&
        routeGroup.items.first.driverRouteName != null) {
      return routeGroup.items.first.driverRouteName!;
    }
    return 'Route ${routeGroup.routeId.substring(0, 8)}';
  }

  String get _capText {
    if (routeGroup.capacityTotal != null &&
        routeGroup.capacityAvailable != null) {
      return 'Seats: ${routeGroup.capacityAvailable} / ${routeGroup.capacityTotal}';
    }
    return 'Seats: n/a';
  }

  Color _statusColor(String status) {
    return statusColorBuilder?.call(status) ?? _defaultStatusColor(status);
  }

  Color _defaultStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'en_route':
        return _purple;
      case 'completed':
        return Colors.green;
      case 'declined':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  List<Widget> _buildMatchList(
    String label,
    List<MatchCard> list, {
    bool selectable = false,
  }) {
    if (list.isEmpty) return [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: _purpleDark,
          ),
        ),
      ),
      ...list.map((m) {
        final canOpenRide =
            m.status == 'accepted' || m.status == 'en_route' || m.status == 'completed';
        final isSelected = routeGroup.selected.contains(m.matchId);

        return MatchListTile(
          match: m,
          selectable: selectable,
          selected: selectable ? isSelected : false,
          onSelect: selectable
              ? (v) => onToggleSelection?.call(m.matchId)
              : null,
          onDecline: onDeclineMatch != null ? () => onDeclineMatch!(m) : null,
          onOpenRide: canOpenRide ? () => onOpenRide?.call(m) : null,
          onChat: onChat != null ? () => onChat!(m) : null,
          onTapRating: onTapRating != null ? () => onTapRating!(m) : null,
          statusColor: _statusColor(m.status),
        );
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.8),
            Colors.white.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          collapsedBackgroundColor: Colors.white.withValues(alpha: 0.9),
          backgroundColor: Colors.white,
          leading: const Icon(Icons.alt_route, color: _purple),
          title: Text(
            _routeTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: _purpleDark,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                RidePill(text: _capText, icon: Icons.event_seat),
                RidePill(
                  text: 'Pending: ${_pending.length}',
                  icon: Icons.hourglass_bottom,
                ),
                RidePill(text: 'Accepted: ${_accepted.length}', icon: Icons.check_circle),
                RidePill(
                  text: 'En route: ${_enRoute.length}',
                  icon: Icons.directions_car,
                ),
              ],
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onViewAllPickups != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.map),
                      label: const Text('Map: all pickups'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _purple,
                        side: const BorderSide(color: _purple),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed:
                          routeGroup.items.any((m) => m.hasCoords)
                              ? () => onViewAllPickups!(routeGroup)
                              : null,
                    ),
                  if (onSelectAllPending != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.select_all),
                      label: const Text('Select all pending'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _purple,
                        side: const BorderSide(color: _purple),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed:
                          _pending.isEmpty
                              ? null
                              : () => onSelectAllPending!(routeGroup.routeId),
                    ),
                  if (onClearSelection != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear selection'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _purple,
                        side: const BorderSide(color: _purple),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed:
                          routeGroup.selected.isEmpty
                              ? null
                              : () => onClearSelection!(routeGroup.routeId),
                    ),
                  if (onAcceptSelected != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.done_all),
                      label: const Text('Accept selected'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
                      ),
                      onPressed:
                          routeGroup.selected.isEmpty
                              ? null
                              : () => onAcceptSelected!(routeGroup),
                    ),
                  if (onStartRoute != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start route'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
                      ),
                      onPressed: _accepted.isEmpty ? null : () => onStartRoute!(routeGroup),
                    ),
                  if (onCompleteRoute != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Complete route'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purpleDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
                      ),
                      onPressed: _enRoute.isEmpty ? null : () => onCompleteRoute!(routeGroup),
                    ),
                ],
              ),
            ),
            const Divider(height: 12, thickness: 0.5),
            const SizedBox(height: 4),
            ..._buildMatchList('Pending', _pending, selectable: true),
            ..._buildMatchList('Accepted', _accepted, selectable: false),
            ..._buildMatchList('En route', _enRoute, selectable: false),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

