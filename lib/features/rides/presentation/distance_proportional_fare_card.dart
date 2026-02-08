// lib/features/rides/presentation/distance_proportional_fare_card.dart
import 'package:flutter/material.dart';
import 'package:godavao/core/fare_service.dart';

/// Widget displaying distance-proportional fare breakdown for shared rides.
///
/// Shows how the total route fare is split among passengers based on
/// their individual traveled distances.
class DistanceProportionalFareCard extends StatelessWidget {
  final SharedFareBreakdown breakdown;
  final String? currentPassengerId;
  final VoidCallback? onTap;

  const DistanceProportionalFareCard({
    super.key,
    required this.breakdown,
    this.currentPassengerId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPassengerFare = currentPassengerId != null
        ? breakdown.passengerFares.firstWhere(
            (p) => p.passengerId == currentPassengerId,
            orElse: () => breakdown.passengerFares.first,
          )
        : null;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.people_outline,
                    color: theme.primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Distance-Proportional Pricing',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.secondary,
                      size: 20,
                    ),
                ],
              ),
              const Divider(height: 24),

              // Current passenger fare (highlighted)
              if (currentPassengerFare != null) ...[
                _buildSectionTitle('Your Fare'),
                const SizedBox(height: 8),
                _buildPassengerFareRow(
                  context,
                  currentPassengerFare,
                  isHighlighted: true,
                ),
                const SizedBox(height: 16),
              ],

              // Route summary
              _buildSectionTitle('Route Summary'),
              const SizedBox(height: 8),
              _buildRouteSummary(context),

              const SizedBox(height: 16),

              // All passengers breakdown
              _buildSectionTitle('Fare Split by Passenger'),
              const SizedBox(height: 8),
              ...breakdown.passengerFares.map((fare) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildPassengerFareRow(
                      context,
                      fare,
                      isCurrent: currentPassengerId != null &&
                          fare.passengerId == currentPassengerId,
                    ),
                  )),

              const SizedBox(height: 16),

              // Total collected
              _buildTotalRow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildRouteSummary(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSummaryItem(
            'Distance',
            '${breakdown.totalRouteDistanceKm.toStringAsFixed(1)} km',
            Icons.straighten,
          ),
          _buildSummaryItem(
            'Duration',
            '${breakdown.durationMin.toStringAsFixed(0)} min',
            Icons.access_time,
          ),
          _buildSummaryItem(
            'Passengers',
            '${breakdown.passengerFares.length}',
            Icons.people,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPassengerFareRow(
    BuildContext context,
    PassengerFare fare, {
    bool isHighlighted = false,
    bool isCurrent = false,
  }) {
    final theme = Theme.of(context);
    final distanceShare = fare.distanceKm / breakdown.totalRouteDistanceKm;
    final percentage = (distanceShare * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isHighlighted
            ? theme.primaryColor.withValues(alpha: 0.1)
            : isCurrent
                ? Colors.amber.withValues(alpha: 0.1)
                : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: isHighlighted
            ? Border.all(color: theme.primaryColor, width: 1)
            : isCurrent
                ? Border.all(color: Colors.amber, width: 1)
                : null,
      ),
      child: Row(
        children: [
          // Passenger indicator
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isHighlighted
                  ? theme.primaryColor
                  : isCurrent
                      ? Colors.amber
                      : Colors.grey[400],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'P',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Passenger details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Passenger ${fare.passengerId.substring(0, 8)}',
                  style: TextStyle(
                    fontWeight: isHighlighted || isCurrent
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fare.distanceKm.toStringAsFixed(1)} km ($percentage% of route)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          // Fare amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${fare.total.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isHighlighted || isCurrent
                      ? theme.primaryColor
                      : Colors.black87,
                ),
              ),
              if (fare.platformFee > 0)
                Text(
                  'incl. ₱${fare.platformFee.toStringAsFixed(0)} fee',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total Collected',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            '₱${breakdown.totalFare.toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: theme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
