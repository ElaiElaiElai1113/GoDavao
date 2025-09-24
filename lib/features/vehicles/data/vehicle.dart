import 'package:equatable/equatable.dart';

class Vehicle extends Equatable {
  final String id;
  final String driverId;
  final String plate;
  final String make;
  final String model;
  final String? color;
  final int? year;
  final int? seats;
  final bool isPrimary;
  final String verificationStatus; // 'pending' | 'verified' | 'rejected'
  final String? verificationReason;

  // NEW
  final String? orNumber;
  final String? crNumber;
  final String? orKey;
  final String? crKey;

  const Vehicle({
    required this.id,
    required this.driverId,
    required this.plate,
    required this.make,
    required this.model,
    this.color,
    this.year,
    this.seats,
    required this.isPrimary,
    required this.verificationStatus,
    this.verificationReason,
    this.orNumber,
    this.crNumber,
    this.orKey,
    this.crKey,
  });

  factory Vehicle.fromMap(Map<String, dynamic> m) => Vehicle(
    id: m['id'].toString(),
    driverId: m['driver_id'].toString(),
    plate: (m['plate'] as String).trim(),
    make: (m['make'] as String).trim(),
    model: (m['model'] as String).trim(),
    color: (m['color'] as String?)?.trim(),
    year: (m['year'] as int?),
    seats: (m['seats'] as int?),
    isPrimary: (m['is_primary'] as bool? ?? false),
    verificationStatus: (m['verification_status'] as String?) ?? 'pending',
    verificationReason: m['verification_reason'] as String?,
    orNumber: m['or_number'] as String?,
    crNumber: m['cr_number'] as String?,
    orKey: m['or_key'] as String?,
    crKey: m['cr_key'] as String?,
  );

  Map<String, dynamic> toInsert() => {
    'plate': plate,
    'make': make,
    'model': model,
    if (color != null) 'color': color,
    if (year != null) 'year': year,
    if (seats != null) 'seats': seats,
    if (orNumber != null) 'or_number': orNumber,
    if (crNumber != null) 'cr_number': crNumber,
  };

  Map<String, dynamic> toUpdate() => {
    'plate': plate,
    'make': make,
    'model': model,
    'color': color,
    'year': year,
    'seats': seats,
    'or_number': orNumber,
    'cr_number': crNumber,
  };

  @override
  List<Object?> get props => [
    id,
    driverId,
    plate,
    make,
    model,
    color,
    year,
    seats,
    isPrimary,
    verificationStatus,
    verificationReason,
    orNumber,
    crNumber,
    orKey,
    crKey,
  ];
}
