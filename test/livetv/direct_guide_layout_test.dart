import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:moonfin/ui/screens/livetv/direct_guide_layout.dart';

DirectChannel _channel({
  required String id,
  required String name,
  String? number,
  String? group,
}) {
  return DirectChannel(
    id: id,
    sourceId: 'src',
    name: name,
    streamUrl: 'http://example.test/$id',
    number: number,
    group: group,
  );
}

DirectProgram _program({
  required String id,
  required String channelId,
  required DateTime start,
  required DateTime end,
  String title = 'Show',
  List<String> categories = const [],
}) {
  return DirectProgram(
    id: id,
    channelKey: channelId,
    title: title,
    start: start,
    end: end,
    categories: categories,
  );
}

void main() {
  test('groups are the M3U titles, blanks dropped, sorted ignoring case', () {
    final groups = directGuideGroups([
      _channel(id: 'a', name: 'A', group: 'Sports'),
      _channel(id: 'b', name: 'B', group: 'news'),
      _channel(id: 'c', name: 'C', group: 'Sports'),
      _channel(id: 'd', name: 'D', group: '  '),
      _channel(id: 'e', name: 'E'),
      _channel(id: 'f', name: 'F', group: 'Movies'),
    ]);

    expect(groups, ['Movies', 'news', 'Sports']);
  });

  test('visible channels filter by group and by name or number', () {
    final channels = [
      _channel(id: 'a', name: 'ESPN', number: '10', group: 'Sports'),
      _channel(id: 'b', name: 'News 5', number: '5', group: 'News'),
      _channel(id: 'c', name: 'Local', number: '2', group: 'News'),
    ];

    expect(
      visibleDirectChannels(channels: channels, group: null).map((c) => c.id),
      ['c', 'b', 'a'],
    );
    expect(
      visibleDirectChannels(channels: channels, group: 'News').map((c) => c.id),
      ['c', 'b'],
    );
    expect(
      visibleDirectChannels(
        channels: channels,
        group: null,
        query: 'espn',
      ).map((c) => c.id),
      ['a'],
    );
    expect(
      visibleDirectChannels(
        channels: channels,
        group: 'News',
        query: '5',
      ).map((c) => c.id),
      ['b'],
    );
  });

  test('window starts on the half hour and spans the requested slots', () {
    final window = directGuideWindow(
      DateTime(2026, 10, 22, 14, 46, 12),
      halfHours: 6,
    );
    expect(window.start, DateTime(2026, 10, 22, 14, 30));
    expect(window.end, DateTime(2026, 10, 22, 17, 30));
    expect(directGuideHalfHours(window), [
      DateTime(2026, 10, 22, 14, 30),
      DateTime(2026, 10, 22, 15),
      DateTime(2026, 10, 22, 15, 30),
      DateTime(2026, 10, 22, 16),
      DateTime(2026, 10, 22, 16, 30),
      DateTime(2026, 10, 22, 17),
    ]);
    expect(
      directGuideWindow(DateTime(2026, 10, 22, 14, 30), halfHours: 4).start,
      DateTime(2026, 10, 22, 14, 30),
    );
  });

  test('now line sits on the fraction of the window already elapsed', () {
    final window = directGuideWindow(
      DateTime(2026, 10, 22, 14, 15),
      halfHours: 6,
    );
    expect(
      directGuideFraction(window, DateTime(2026, 10, 22, 14, 15)),
      closeTo(15 / 180, 0.0001),
    );
    expect(directGuideFraction(window, DateTime(2026, 10, 22, 13)), 0);
    expect(directGuideFraction(window, DateTime(2026, 10, 22, 20)), 1);
  });

  test(
    'blocks are clipped to the window and sized by the visible duration',
    () {
      final window = DirectGuideWindow(
        start: DateTime(2026, 10, 22, 14),
        end: DateTime(2026, 10, 22, 17),
      );
      final blocks = directGuideBlocks(
        window: window,
        programs: [
          _program(
            id: 'past',
            channelId: 'a',
            start: DateTime(2026, 10, 22, 12),
            end: DateTime(2026, 10, 22, 13),
          ),
          _program(
            id: 'movie',
            channelId: 'a',
            start: DateTime(2026, 10, 22, 13),
            end: DateTime(2026, 10, 22, 16),
          ),
          _program(
            id: 'next',
            channelId: 'a',
            start: DateTime(2026, 10, 22, 16, 30),
            end: DateTime(2026, 10, 22, 18),
          ),
        ],
      );

      expect(blocks.map((block) => block.program?.id), ['movie', 'next']);
      expect(blocks[0].visibleStart, window.start);
      expect(blocks[0].visibleEnd, DateTime(2026, 10, 22, 16));
      expect(blocks[0].left(window), 0);
      expect(blocks[0].width(window), closeTo(2 / 3, 0.0001));
      expect(blocks[1].left(window), closeTo(2.5 / 3, 0.0001));
      expect(blocks[1].width(window), closeTo(0.5 / 3, 0.0001));
    },
  );

  test(
    'a channel with nothing in the window still has one focusable block',
    () {
      final window = DirectGuideWindow(
        start: DateTime(2026, 10, 22, 14),
        end: DateTime(2026, 10, 22, 17),
      );
      final blocks = directGuideBlocks(programs: const [], window: window);
      expect(blocks, hasLength(1));
      expect(blocks.single.program, isNull);
      expect(blocks.single.width(window), 1);
    },
  );

  test('cursor moves across blocks and keeps the clock when changing rows', () {
    final window = DirectGuideWindow(
      start: DateTime(2026, 10, 22, 14),
      end: DateTime(2026, 10, 22, 17),
    );
    final now = DateTime(2026, 10, 22, 14, 20);
    final rows = [
      directGuideBlocks(
        window: window,
        programs: [
          _program(
            id: 'a-now',
            channelId: 'a',
            start: DateTime(2026, 10, 22, 14),
            end: DateTime(2026, 10, 22, 15),
          ),
          _program(
            id: 'a-next',
            channelId: 'a',
            start: DateTime(2026, 10, 22, 15),
            end: DateTime(2026, 10, 22, 16),
          ),
        ],
      ),
      directGuideBlocks(
        window: window,
        programs: [
          _program(
            id: 'b-long',
            channelId: 'b',
            start: DateTime(2026, 10, 22, 13),
            end: DateTime(2026, 10, 22, 16),
          ),
        ],
      ),
      directGuideBlocks(window: window, programs: const []),
    ];

    List<DirectGuideBlock> blocksForRow(int row) => rows[row];

    final right = moveDirectGuideCursor(
      cursor: const DirectGuideCursor(row: 0, programId: 'a-now'),
      move: DirectGuideMove.right,
      rowCount: rows.length,
      blocksForRow: blocksForRow,
      now: now,
    );
    expect(right.programId, 'a-next');

    final down = moveDirectGuideCursor(
      cursor: const DirectGuideCursor(row: 0, programId: 'a-now'),
      move: DirectGuideMove.down,
      rowCount: rows.length,
      blocksForRow: blocksForRow,
      now: now,
    );
    expect(down.row, 1);
    expect(down.programId, 'b-long');

    final fromFuture = moveDirectGuideCursor(
      cursor: const DirectGuideCursor(row: 0, programId: 'a-next'),
      move: DirectGuideMove.down,
      rowCount: rows.length,
      blocksForRow: blocksForRow,
      now: now,
    );
    expect(fromFuture.programId, 'b-long');

    final placeholder = moveDirectGuideCursor(
      cursor: const DirectGuideCursor(row: 1, programId: 'b-long'),
      move: DirectGuideMove.down,
      rowCount: rows.length,
      blocksForRow: blocksForRow,
      now: now,
    );
    expect(placeholder.row, 2);
    expect(placeholder.programId, isNull);

    final stayed = moveDirectGuideCursor(
      cursor: const DirectGuideCursor(row: 0, programId: 'a-now'),
      move: DirectGuideMove.left,
      rowCount: rows.length,
      blocksForRow: blocksForRow,
      now: now,
    );
    expect(stayed.row, 0);
    expect(stayed.programId, 'a-now');

    final paged = pageDirectGuideCursor(
      cursor: const DirectGuideCursor(row: 0, programId: 'a-now'),
      deltaRows: 5,
      rowCount: rows.length,
      blocksForRow: blocksForRow,
      now: now,
    );
    expect(paged.row, 2);
  });

  test('type tag, progress, and the sidebar clock', () {
    final program = _program(
      id: 'p',
      channelId: 'a',
      start: DateTime(2026, 10, 22, 14),
      end: DateTime(2026, 10, 22, 15),
      categories: const ['Sports'],
    );
    expect(directProgramTypeTag(program), 'Sports');
    expect(
      directProgramTypeTag(
        _program(
          id: 'm',
          channelId: 'a',
          start: program.start,
          end: program.end,
          categories: const ['Movie', 'Drama'],
        ),
      ),
      'Movie',
    );
    expect(
      directProgramTypeTag(
        _program(
          id: 'empty',
          channelId: 'a',
          start: program.start,
          end: program.end,
        ),
      ),
      'TV',
    );
    expect(
      directProgramProgress(program, DateTime(2026, 10, 22, 14, 30)),
      closeTo(0.5, 0.0001),
    );
    expect(directProgramProgress(program, DateTime(2026, 10, 22, 13)), 0);
    expect(directProgramProgress(program, DateTime(2026, 10, 22, 16)), 1);
    expect(formatGuideTime(DateTime(2026, 10, 22, 14, 46)), '2:46 PM');
    expect(formatGuideTime(DateTime(2026, 10, 22)), '12:00 AM');
    expect(formatGuideTime(DateTime(2026, 10, 22, 12)), '12:00 PM');
    expect(formatGuideDate(DateTime(2026, 10, 22, 14, 46)), 'Thu, Oct 22');
    expect(directProgramTimeRange(program), '2:00 PM – 3:00 PM');
  });
}
