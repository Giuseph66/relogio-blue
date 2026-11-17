import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BundleStorage {
  Future<File> _file() async => File(p.join(await getDatabasesPath(), 'offline_bundle.json'));
  Future<String?> read() async {
    final file = await _file();
    return await file.exists() ? file.readAsString() : null;
  }
  Future<void> write(String value) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename(file.path);
  }
}
