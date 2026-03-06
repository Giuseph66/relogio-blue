import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/tracked_location.dart';
import '../../domain/entities/location_visit.dart';

class LocationTrackerRepository {
  static const String _keyLocations = 'tracked_locations';
  static const String _keyVisits = 'location_visits';

  Future<Result<List<TrackedLocation>, String>> getLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_keyLocations);
      if (jsonStr == null || jsonStr.isEmpty) return const Success([]);

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final locations = jsonList.map((json) => TrackedLocation.fromJson(json)).toList();
      return Success(locations);
    } catch (e) {
      return Failure(e.toString());
    }
  }

  Future<Result<void, String>> saveLocations(List<TrackedLocation> locations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(locations.map((loc) => loc.toJson()).toList());
      await prefs.setString(_keyLocations, jsonStr);
      return const Success(null);
    } catch (e) {
      return Failure(e.toString());
    }
  }

  Future<Result<List<LocationVisit>, String>> getVisits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_keyVisits);
      if (jsonStr == null || jsonStr.isEmpty) return const Success([]);

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final visits = jsonList.map((json) => LocationVisit.fromJson(json)).toList();
      return Success(visits);
    } catch (e) {
      return Failure(e.toString());
    }
  }

  Future<Result<void, String>> saveVisits(List<LocationVisit> visits) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(visits.map((v) => v.toJson()).toList());
      await prefs.setString(_keyVisits, jsonStr);
      return const Success(null);
    } catch (e) {
      return Failure(e.toString());
    }
  }
}
