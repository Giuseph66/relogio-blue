/// Simple logger for the app
class AppLogger {
  static const String _tag = '[Relógio BLE]';
  
  static void debug(String message) {
    print('$_tag [DEBUG] $message');
  }
  
  static void info(String message) {
    print('$_tag [INFO] $message');
  }
  
  static void warning(String message) {
    print('$_tag [WARNING] $message');
  }
  
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('$_tag [ERROR] $message');
    if (error != null) {
      print('$_tag [ERROR] Error: $error');
    }
    if (stackTrace != null) {
      print('$_tag [ERROR] StackTrace: $stackTrace');
    }
  }
}

