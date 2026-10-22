import '../../../direct_iptv/models.dart';

/// "All Channels" is the null group. Playlist group-titles are listed once,
/// blank names dropped, and the rest ordered case-insensitively.
List<String> directGuideGroups(Iterable<DirectChannel> channels) {
  final names = <String>{
    for (final channel in channels)
      if (channel.group != null && channel.group!.trim().isNotEmpty)
        channel.group!,
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names;
}

/// Numeric channel numbers first, then names. Same rule the old list used,
/// with a name tie-break so two channels that share a number stay put.
int compareDirectChannels(DirectChannel a, DirectChannel b) {
  final left = double.tryParse(a.number ?? '');
  final right = double.tryParse(b.number ?? '');
  if (left != null && right != null) {
    final byNumber = left.compareTo(right);
    if (byNumber != 0) return byNumber;
  } else if (left != null) {
    return -1;
  } else if (right != null) {
    return 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

List<DirectChannel> visibleDirectChannels({
  required List<DirectChannel> channels,
  String? group,
  String query = '',
}) {
  final needle = query.trim().toLowerCase();
  final visible = channels.where((channel) {
    if (group != null && channel.group != group) return false;
    if (needle.isEmpty) return true;
    final number = channel.number ?? '';
    return channel.name.toLowerCase().contains(needle) ||
        number.toLowerCase().contains(needle);
  }).toList()..sort(compareDirectChannels);
  return visible;
}

Map<String, List<DirectProgram>> indexDirectPrograms(
  Iterable<DirectProgram> programs,
) {
  final index = <String, List<DirectProgram>>{};
  for (final program in programs) {
    (index[program.channelKey] ??= []).add(program);
  }
  for (final list in index.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  return index;
}

/// Floors to the top or bottom of the hour, dropping seconds.
DateTime floorToDirectHalfHour(DateTime time) => DateTime(
  time.year,
  time.month,
  time.day,
  time.hour,
  time.minute - (time.minute % 30),
);

class DirectGuideWindow {
  final DateTime start;
  final DateTime end;

  const DirectGuideWindow({required this.start, required this.end});

  Duration get span => end.difference(start);
}

DirectGuideWindow directGuideWindow(DateTime now, {int halfHours = 6}) {
  final slots = halfHours < 1 ? 1 : halfHours;
  final start = floorToDirectHalfHour(now);
  return DirectGuideWindow(
    start: start,
    end: start.add(Duration(minutes: 30 * slots)),
  );
}

List<DateTime> directGuideHalfHours(DirectGuideWindow window) {
  final marks = <DateTime>[];
  var cursor = window.start;
  while (cursor.isBefore(window.end)) {
    marks.add(cursor);
    cursor = cursor.add(const Duration(minutes: 30));
  }
  return marks;
}

double directGuideFraction(DirectGuideWindow window, DateTime time) {
  final total = window.end.difference(window.start).inMilliseconds;
  if (total <= 0) return 0;
  final elapsed = time.difference(window.start).inMilliseconds;
  final fraction = elapsed / total;
  if (fraction < 0) return 0;
  if (fraction > 1) return 1;
  return fraction;
}

/// One painted program, already clipped to the window. A null [program] is
/// the row's placeholder when the guide has nothing in range.
class DirectGuideBlock {
  final DirectProgram? program;
  final DateTime visibleStart;
  final DateTime visibleEnd;

  const DirectGuideBlock({
    required this.program,
    required this.visibleStart,
    required this.visibleEnd,
  });

  double left(DirectGuideWindow window) =>
      directGuideFraction(window, visibleStart);

  double width(DirectGuideWindow window) {
    final size = directGuideFraction(window, visibleEnd) - left(window);
    return size < 0 ? 0 : size;
  }
}

List<DirectGuideBlock> directGuideBlocks({
  required List<DirectProgram> programs,
  required DirectGuideWindow window,
}) {
  final blocks = <DirectGuideBlock>[];
  for (final program in programs) {
    if (!program.end.isAfter(window.start)) continue;
    if (!program.start.isBefore(window.end)) continue;
    final visibleStart = program.start.isBefore(window.start)
        ? window.start
        : program.start;
    final visibleEnd = program.end.isAfter(window.end)
        ? window.end
        : program.end;
    if (!visibleEnd.isAfter(visibleStart)) continue;
    blocks.add(
      DirectGuideBlock(
        program: program,
        visibleStart: visibleStart,
        visibleEnd: visibleEnd,
      ),
    );
  }
  blocks.sort((a, b) => a.visibleStart.compareTo(b.visibleStart));
  if (blocks.isNotEmpty) return blocks;
  return [
    DirectGuideBlock(
      program: null,
      visibleStart: window.start,
      visibleEnd: window.end,
    ),
  ];
}

int directGuideBlockIndex(
  List<DirectGuideBlock> blocks,
  String? programId,
  DateTime anchor,
) {
  if (blocks.isEmpty) return 0;
  if (programId != null) {
    final match = blocks.indexWhere((block) => block.program?.id == programId);
    if (match >= 0) return match;
  }
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (!anchor.isBefore(block.visibleStart) &&
        anchor.isBefore(block.visibleEnd)) {
      return i;
    }
  }
  if (!anchor.isBefore(blocks.first.visibleStart)) {
    return blocks.length - 1;
  }
  return 0;
}

/// Up and down keep the clock position. A live block uses "now" so the next
/// row lands on whatever is airing, not on the start of a long show.
DateTime directGuideVerticalAnchor(DirectGuideBlock block, DateTime now) {
  if (!now.isBefore(block.visibleStart) && now.isBefore(block.visibleEnd)) {
    return now;
  }
  return block.visibleStart;
}

class DirectGuideCursor {
  final int row;
  final String? programId;

  const DirectGuideCursor({required this.row, this.programId});
}

enum DirectGuideMove { left, right, up, down }

DirectGuideCursor moveDirectGuideCursor({
  required DirectGuideCursor cursor,
  required DirectGuideMove move,
  required int rowCount,
  required List<DirectGuideBlock> Function(int row) blocksForRow,
  required DateTime now,
}) {
  if (rowCount <= 0) return cursor;
  final row = cursor.row.clamp(0, rowCount - 1);
  final blocks = blocksForRow(row);
  final index = directGuideBlockIndex(blocks, cursor.programId, now);
  final block = blocks[index];
  switch (move) {
    case DirectGuideMove.left:
      final previous = index <= 0 ? index : index - 1;
      return DirectGuideCursor(
        row: row,
        programId: blocks[previous].program?.id,
      );
    case DirectGuideMove.right:
      final next = index >= blocks.length - 1 ? index : index + 1;
      return DirectGuideCursor(row: row, programId: blocks[next].program?.id);
    case DirectGuideMove.up:
      if (row <= 0) {
        return DirectGuideCursor(row: row, programId: block.program?.id);
      }
      return _cursorAtAnchor(
        row: row - 1,
        anchor: directGuideVerticalAnchor(block, now),
        blocksForRow: blocksForRow,
      );
    case DirectGuideMove.down:
      if (row >= rowCount - 1) {
        return DirectGuideCursor(row: row, programId: block.program?.id);
      }
      return _cursorAtAnchor(
        row: row + 1,
        anchor: directGuideVerticalAnchor(block, now),
        blocksForRow: blocksForRow,
      );
  }
}

DirectGuideCursor pageDirectGuideCursor({
  required DirectGuideCursor cursor,
  required int deltaRows,
  required int rowCount,
  required List<DirectGuideBlock> Function(int row) blocksForRow,
  required DateTime now,
}) {
  if (rowCount <= 0 || deltaRows == 0) return cursor;
  final row = cursor.row.clamp(0, rowCount - 1);
  final nextRow = (row + deltaRows).clamp(0, rowCount - 1);
  final blocks = blocksForRow(row);
  final index = directGuideBlockIndex(blocks, cursor.programId, now);
  final anchor = directGuideVerticalAnchor(blocks[index], now);
  return _cursorAtAnchor(
    row: nextRow,
    anchor: anchor,
    blocksForRow: blocksForRow,
  );
}

DirectGuideCursor _cursorAtAnchor({
  required int row,
  required DateTime anchor,
  required List<DirectGuideBlock> Function(int row) blocksForRow,
}) {
  final blocks = blocksForRow(row);
  final index = directGuideBlockIndex(blocks, null, anchor);
  return DirectGuideCursor(row: row, programId: blocks[index].program?.id);
}

/// Movie, sports, news, kids, then series. Otherwise the first category,
/// or "TV" when the guide didn't say.
String directProgramTypeTag(DirectProgram program) {
  final categories = [
    for (final category in program.categories) category.toLowerCase(),
  ];
  bool has(String needle) =>
      categories.any((category) => category.contains(needle));
  if (has('movie') || has('film')) return 'Movie';
  if (has('sport')) return 'Sports';
  if (has('news')) return 'News';
  if (has('kids') || has('child')) return 'Kids';
  if (has('series') || has('episode')) return 'Series';
  for (final category in program.categories) {
    final raw = category.trim();
    if (raw.isEmpty) continue;
    return raw[0].toUpperCase() + raw.substring(1);
  }
  return 'TV';
}

double directProgramProgress(DirectProgram program, DateTime now) {
  final total = program.end.difference(program.start).inMilliseconds;
  if (total <= 0) return 0;
  final elapsed = now.difference(program.start).inMilliseconds;
  final fraction = elapsed / total;
  if (fraction < 0) return 0;
  if (fraction > 1) return 1;
  return fraction;
}

const directGuideWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const directGuideMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatGuideTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String formatGuideDate(DateTime time) {
  final weekday = directGuideWeekdays[time.weekday - 1];
  final month = directGuideMonths[time.month - 1];
  return '$weekday, $month ${time.day}';
}

String directProgramTimeRange(DirectProgram program) =>
    '${formatGuideTime(program.start)} – ${formatGuideTime(program.end)}';
