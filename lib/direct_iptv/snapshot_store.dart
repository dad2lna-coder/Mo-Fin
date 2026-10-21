import 'models.dart';

/// Disk or memory cache of a parsed lineup. The catalog keeps credentials
/// out of this snapshot.
abstract class DirectIptvSnapshotStore {
  Future<DirectIptvSnapshot?> read(String sourceId);
  Future<void> write(DirectIptvSnapshot snapshot);
  Future<void> delete(String sourceId);
}

class MemoryDirectIptvSnapshotStore implements DirectIptvSnapshotStore {
  final Map<String, DirectIptvSnapshot> items = {};

  @override
  Future<DirectIptvSnapshot?> read(String sourceId) async => items[sourceId];

  @override
  Future<void> write(DirectIptvSnapshot snapshot) async {
    items[snapshot.sourceId] = snapshot;
  }

  @override
  Future<void> delete(String sourceId) async {
    items.remove(sourceId);
  }
}
