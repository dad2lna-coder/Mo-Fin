import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/game_library.dart';

void main() {
  test('strips trailing region, revision, and dump tags', () {
    expect(
      gameDisplayTitle(
        '3 Ninjas Kick Back (USA)',
        '3 Ninjas Kick Back (USA).sfc',
      ),
      '3 Ninjas Kick Back',
    );
    expect(
      gameDisplayTitle(
        '3 Ninjas Kick Back (USA) (Rev 1)',
        '3 Ninjas Kick Back (USA) (Rev 1).sfc',
      ),
      '3 Ninjas Kick Back',
    );
    expect(
      gameDisplayTitle('ActRaiser [!] [T+Eng]', 'ActRaiser [!] [T+Eng].sfc'),
      'ActRaiser',
    );
  });

  test('moves a trailing article to the front', () {
    expect(
      gameDisplayTitle(
        'Legend of Zelda, The (USA)',
        'Legend of Zelda, The.sfc',
      ),
      'The Legend of Zelda',
    );
    expect(
      gameDisplayTitle('River City, A', 'River City, A.nes'),
      'A River City',
    );
  });

  test('keeps a title that is not a filename when choosing a folder name', () {
    expect(
      preferGameFolderTitle(
        title: '3x3 Eyes - Juuma Houkan (Japan)',
        fileName: '3x3 Eyes (Japan).smc',
        folderTitle: '3x3 Eyes',
      ),
      '3x3 Eyes - Juuma Houkan (Japan)',
    );
    expect(
      preferGameFolderTitle(
        title: '3x3 Eyes (Japan).smc',
        fileName: '3x3 Eyes (Japan).smc',
        folderTitle: '3x3 Eyes',
      ),
      '3x3 Eyes',
    );
  });
}
