export 'package:geocoding/geocoding.dart' show Placemark, Location;
export 'app_geocoding_native.dart'
    if (dart.library.js_interop) 'app_geocoding_web.dart';
