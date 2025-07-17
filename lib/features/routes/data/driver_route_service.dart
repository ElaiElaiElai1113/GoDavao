import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver_route_model.dart';

class DriverRouteService {
  final _client = Supabase.instance.client;

  Future<void> saveRoute(DriverRoute route) async {
    await _client.from('driver_routes').insert(route.toMap());
  }
}
