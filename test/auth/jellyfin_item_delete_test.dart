import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/jellyfin_item_delete.dart';
import 'package:server_core/server_core.dart';

void main() {
  test('delete is allowed for a Jellyfin admin movie or episode', () {
    expect(
      canDeleteOwnJellyfinItem(
        serverType: ServerType.jellyfin,
        isAdministrator: true,
        canDeleteContent: false,
        itemType: 'Movie',
      ),
      isTrue,
    );
    expect(
      canDeleteOwnJellyfinItem(
        serverType: ServerType.jellyfin,
        isAdministrator: true,
        canDeleteContent: false,
        itemType: 'Episode',
      ),
      isTrue,
    );
  });

  test('content deletion allows a non-admin the same two types', () {
    expect(
      canDeleteOwnJellyfinItem(
        serverType: ServerType.jellyfin,
        isAdministrator: false,
        canDeleteContent: true,
        itemType: 'Movie',
      ),
      isTrue,
    );
    expect(
      canDeleteOwnJellyfinItem(
        serverType: ServerType.jellyfin,
        isAdministrator: false,
        canDeleteContent: true,
        itemType: 'Episode',
      ),
      isTrue,
    );
  });

  test('a user with neither flag cannot delete', () {
    expect(
      canDeleteOwnJellyfinItem(
        serverType: ServerType.jellyfin,
        isAdministrator: false,
        canDeleteContent: false,
        itemType: 'Movie',
      ),
      isFalse,
    );
  });

  test('live TV and other types stay even for an admin', () {
    for (final type in [
      'TvChannel',
      'Program',
      'Series',
      'Season',
      'Recording',
      'Video',
      'Audio',
      'BoxSet',
      null,
      '',
    ]) {
      expect(
        canDeleteOwnJellyfinItem(
          serverType: ServerType.jellyfin,
          isAdministrator: true,
          canDeleteContent: true,
          itemType: type,
        ),
        isFalse,
        reason: type ?? 'null',
      );
    }
  });

  test('an Emby admin cannot use this delete', () {
    expect(
      canDeleteOwnJellyfinItem(
        serverType: ServerType.emby,
        isAdministrator: true,
        canDeleteContent: true,
        itemType: 'Movie',
      ),
      isFalse,
    );
    expect(
      canDeleteOwnJellyfinItem(
        serverType: ServerType.emby,
        isAdministrator: true,
        canDeleteContent: true,
        itemType: 'Episode',
      ),
      isFalse,
    );
  });

  test('confirm copy names the title and failure copy follows status', () {
    expect(
      jellyfinDeleteConfirmMessage('The Wire'),
      "Delete The Wire from the server? This can't be undone.",
    );
    expect(
      jellyfinDeleteConfirmMessage('  '),
      "Delete this video from the server? This can't be undone.",
    );
    expect(jellyfinDeleteFailureMessage(401), 'Not allowed');
    expect(jellyfinDeleteFailureMessage(403), 'Not allowed');
    expect(jellyfinDeleteFailureMessage(500), 'Delete failed');
    expect(jellyfinDeleteFailureMessage(null), 'Delete failed');
  });
}
