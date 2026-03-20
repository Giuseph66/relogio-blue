import 'package:connectivity_plus/connectivity_plus.dart';

/// Exposes a stream that emits [true] when the device has network access
/// and [false] when it does not.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  Stream<bool> get isOnline => _connectivity.onConnectivityChanged.map(
        (results) => results.any(
          (r) =>
              r == ConnectivityResult.mobile ||
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.ethernet,
        ),
      );

  /// Returns the current connectivity state as a one-shot check.
  Future<bool> checkNow() async {
    final results = await _connectivity.checkConnectivity();
    return results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );
  }
}
