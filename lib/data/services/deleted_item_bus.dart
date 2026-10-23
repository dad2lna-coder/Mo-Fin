import 'package:flutter/foundation.dart';

/// A Jellyfin item this user just deleted. Loaded lists drop it immediately
/// instead of waiting for the next home refresh to come back.
final deletedItemBus = DeletedItemBus();

class DeletedItemBus extends ChangeNotifier {
  String? lastId;

  void forget(String itemId) {
    if (itemId.isEmpty) return;
    lastId = itemId;
    notifyListeners();
  }
}
