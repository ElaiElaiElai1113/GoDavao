import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:godavao/common/app_colors.dart';

import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/ride_status/models/match_card_model.dart';

/// A reusable pill widget for displaying small tags with icons.
class RidePill extends StatelessWidget {
  const RidePill({
    super.key,
    required this.text,
    this.icon,
    this.color,
  });

  final String text;
  final IconData? icon;
  final Color? color;

  static const _defaultColor = AppColors.purple;

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? _defaultColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: baseColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: baseColor.withValues(alpha: 0.95)),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: baseColor.withValues(alpha: 0.95),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rating chip widget for displaying user ratings.
class RatingChip extends StatelessWidget {
  const RatingChip({
    super.key,
    required this.avg,
    required this.count,
    this.onTap,
  });

  final double? avg;
  final int? count;
  final VoidCallback? onTap;

  static const _defaultNewRating = 3.0;

  String _getLabel() {
    final isNew = (count == null || count == 0);
    final shown = (isNew ? _defaultNewRating : (avg ?? _defaultNewRating));
    return isNew
        ? '${shown.toStringAsFixed(1)} (new)'
        : '${shown.toStringAsFixed(1)} ($count)';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 14),
            const SizedBox(width: 4),
            Text(
              _getLabel(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// A map thumbnail widget showing pickup and destination points.
class MapThumbnail extends StatelessWidget {
  const MapThumbnail({
    super.key,
    required this.pickup,
    required this.destination,
    this.onTap,
  });

  final LatLng pickup;
  final LatLng destination;
  final VoidCallback? onTap;

  static const _purple = AppColors.purple;
  static const _purpleDark = AppColors.purpleDark;

  @override
  Widget build(BuildContext context) {
    final bounds = LatLngBounds.fromPoints([pickup, destination]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 96,
            child: AbsorbPointer(
              absorbing: true,
              child: FlutterMap(
                options: MapOptions(
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                  initialCenter: bounds.center,
                  initialZoom: 13,
                  initialCameraFit: CameraFit.bounds(bounds: bounds),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.godavao.app',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [pickup, destination],
                        strokeWidth: 3,
                        color: _purpleDark.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pickup,
                        width: 24,
                        height: 24,
                        child: const Icon(
                          Icons.location_pin,
                          color: _purple,
                          size: 24,
                        ),
                      ),
                      Marker(
                        point: destination,
                        width: 22,
                        height: 22,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A list tile widget for displaying match cards with selection and actions.
class MatchListTile extends StatelessWidget {
  const MatchListTile({
    super.key,
    required this.match,
    required this.selected,
    required this.selectable,
    this.onSelect,
    this.onDecline,
    this.onOpenRide,
    this.onChat,
    this.onTapRating,
    this.statusColor,
  });

  final MatchCard match;
  final bool selected;
  final bool selectable;
  final ValueChanged<bool?>? onSelect;
  final VoidCallback? onDecline;
  final VoidCallback? onOpenRide;
  final VoidCallback? onChat;
  final VoidCallback? onTapRating;
  final Color? statusColor;

  static const _defaultStatusColor = AppColors.purple;

  Color get _trailingStatusColor =>
      statusColor ?? _defaultStatusColor;

  bool get _canOpenMap => onOpenRide != null;

  String _formatPeso(num? v) =>
      v == null ? '₱0.00' : '₱${(v.toDouble()).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectable)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 28,
                  child: Checkbox(
                    visualDensity: const VisualDensity(
                      horizontal: -3,
                      vertical: -3,
                    ),
                    value: selected,
                    onChanged: onSelect,
                  ),
                ),
              )
            else
              const SizedBox(width: 4),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${match.pickupAddress} → ${match.destinationAddress}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RidePill(text: '${match.pax} pax', icon: Icons.people_alt),
                      if (match.fare != null)
                        RidePill(text: _formatPeso(match.fare), icon: Icons.payments),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(
                            Icons.person,
                            size: 14,
                            color: Colors.black54,
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              match.passengerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (match.passengerId != null) ...[
                            VerifiedBadge(userId: match.passengerId!, size: 16),
                            UserRatingBadge(
                              userId: match.passengerId!,
                              iconSize: 14,
                            ),
                          ],
                          RatingChip(
                            avg: match.ratingAvg,
                            count: match.ratingCount,
                            onTap: onTapRating,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (match.hasCoords)
                    MapThumbnail(
                      pickup: match.pickup!,
                      destination: match.destination!,
                    ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Trailing column
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _trailingStatusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _trailingStatusColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    match.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: _trailingStatusColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (onChat != null)
                      IconButton(
                        tooltip: 'Chat',
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        onPressed: onChat,
                        icon: const Icon(Icons.message_outlined),
                      ),
                    if (match.status == 'pending' && onDecline != null)
                      IconButton(
                        tooltip: 'Decline',
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        onPressed: onDecline,
                        icon: const Icon(Icons.close),
                      ),
                    if (_canOpenMap)
                      IconButton(
                        tooltip: 'View ride',
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        onPressed: onOpenRide,
                        icon: const Icon(Icons.map_outlined),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

