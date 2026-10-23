import 'package:server_core/server_core.dart';

/// Movies and episodes on a Jellyfin server, and only when this user is an
/// administrator or is allowed to delete content. Live TV and every other
/// item type stay, and so does every non-Jellyfin server.
bool canDeleteOwnJellyfinItem({
  required ServerType serverType,
  required bool isAdministrator,
  required bool canDeleteContent,
  required String? itemType,
}) {
  if (serverType != ServerType.jellyfin) return false;
  if (itemType != 'Movie' && itemType != 'Episode') return false;
  return isAdministrator || canDeleteContent;
}

/// Exact confirm copy. An empty title still names a video.
String jellyfinDeleteConfirmMessage(String title) {
  final name = title.trim().isEmpty ? 'this video' : title.trim();
  return "Delete $name from the server? This can't be undone.";
}

/// 401 and 403 are a permission miss. Everything else, including a missing
/// status, is a failed delete.
String jellyfinDeleteFailureMessage(int? statusCode) {
  if (statusCode == 401 || statusCode == 403) return 'Not allowed';
  return 'Delete failed';
}
