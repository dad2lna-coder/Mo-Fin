import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'snapshot_store.dart';

export 'snapshot_store.dart';

DirectIptvSnapshotStore createDirectIptvSnapshotStore() =>
    const FileDirectIptvSnapshotStore();

class FileDirectIptvSnapshotStore implements DirectIptvSnapshotStore {
  const FileDirectIptvSnapshotStore();

  Future<File> _file(String sourceId) async {
    final root = await getApplicationSupportDirectory();
    final folder = Directory(p.join(root.path, 'direct_iptv'));
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final safe = sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(folder.path, '$safe.json'));
  }

  @override
  Future<DirectIptvSnapshot?> read(String sourceId) async {
    try {
      final file = await _file(sourceId);
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return DirectIptvSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(DirectIptvSnapshot snapshot) async {
    try {
      final file = await _file(snapshot.sourceId);
      await file.writeAsString(jsonEncode(snapshot.toJson()));
    } catch (_) {}
  }

  @override
  Future<void> delete(String sourceId) async {
    try {
      final file = await _file(sourceId);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }
}
