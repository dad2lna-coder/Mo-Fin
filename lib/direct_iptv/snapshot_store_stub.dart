export 'snapshot_store.dart';

import 'snapshot_store.dart';

/// Web has no app-support directory. The lineup stays in memory for the
/// session and is fetched again next launch.
DirectIptvSnapshotStore createDirectIptvSnapshotStore() =>
    MemoryDirectIptvSnapshotStore();
