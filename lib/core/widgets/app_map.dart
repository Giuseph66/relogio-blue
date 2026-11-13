import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';

import '../theme/app_palette.dart';

/// Shared building blocks for the OpenStreetMap-based maps (flutter_map).
/// No API key needed: tiles come from the official OSM tile server and are
/// darkened on-device to match the app theme.
class AppMap {
  AppMap._();

  /// Identifies the app to the tile server (required by the OSM tile policy).
  static const String userAgentPackageName = 'com.example.relogio';

  static const LatLng defaultCenter = LatLng(-23.5505, -46.6333); // São Paulo
  static const double defaultZoom = 15.0;

  /// OSM standard tiles; inverted to a dark style via [fm.darkModeTileBuilder]
  /// only when the dark theme is active.
  static fm.TileLayer tileLayer(BuildContext context) {
    return fm.TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: userAgentPackageName,
      maxNativeZoom: 19,
      tileBuilder: context.isDarkTheme ? fm.darkModeTileBuilder : null,
    );
  }

  /// Attribution required by the OpenStreetMap license.
  static Widget attribution() {
    return Builder(
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Align(
          alignment: Alignment.bottomRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: const Color(0xCC000000),
            child: const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }

  /// "You are here" dot (replaces Google's blue myLocation dot).
  static fm.Marker currentLocation(
    LatLng point, {
    Color color = Colors.cyanAccent,
  }) {
    return fm.Marker(
      point: point,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.25),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }

  /// Classic pin whose tip sits exactly on [point].
  static fm.Marker pin(
    LatLng point, {
    required Color color,
    VoidCallback? onTap,
    double size = 40,
  }) {
    return fm.Marker(
      point: point,
      width: size,
      height: size,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(
          Icons.location_on,
          size: size,
          color: color,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
        ),
      ),
    );
  }

  /// Geofence radius drawn around a saved location.
  static fm.CircleMarker radius(LatLng point, double meters, Color color) {
    return fm.CircleMarker(
      point: point,
      radius: meters,
      useRadiusInMeter: true,
      color: color.withValues(alpha: 0.12),
      borderColor: color.withValues(alpha: 0.6),
      borderStrokeWidth: 1.5,
    );
  }
}
