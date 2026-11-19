import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/log_service.dart';
import 'package:moonfin/data/viewmodels/live_tv_guide_view_model.dart';
import 'package:moonfin/direct_iptv/direct_iptv_catalog.dart';
import 'package:moonfin/direct_iptv/direct_iptv_client.dart';
import 'package:moonfin/direct_iptv/direct_iptv_playback.dart';
import 'package:moonfin/direct_iptv/feed_preference.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:moonfin/direct_iptv/snapshot_store.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/platform/pip_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/livetv/live_tv_player_screen.dart';
import 'package:moonfin/ui/screensaver/screensaver_controller.dart';
import 'package:moonfin/util/platform_detection.dart';

class _Client extends Mock implements MediaServerClient {}

class _LiveTvApi extends Mock implements LiveTvApi {}

class _Log extends Fake implements LogService {
  @override
  void playback(
    String message, {
    LogLevel level = LogLevel.debug,
    Object? error,
  }) {}
}

class _Screensaver extends Fake implements ScreensaverController {
  @override
  void setPlaybackActive(bool active) {}
}

class _Transport extends DirectIptvTransport {
  @override
  Future<DirectIptvHttpResult> get(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    return const DirectIptvHttpResult(404, '');
  }
}

class _Backend extends Fake implements PlayerBackend {
  @override
  LiveSeekWindow? get liveSeekWindow => null;

  @override
  Stream<void> get tracksChangedStream => const Stream.empty();

  @override
  List<EmbeddedCaptionTrack> get embeddedCaptionTracks => const [];

  @override
  List<NativeTextRendition> get nativeTextRenditions => const [];

  @override
  Future<void> configureSubtitleStyle({
    int? textColor,
    int? backgroundColor,
    int? strokeColor,
    double? fontSize,
    int? fontWeight,
    double? verticalOffset,
  }) async {}
}

class _Manager extends PlaybackManager {
  _Manager(this.fakeBackend);

  final _Backend fakeBackend;
  final played = <String>[];
  var pauses = 0;
  var resumes = 0;

  @override
  PlayerBackend? get backend => fakeBackend;

  @override
  Stream<PlaybackBringupState> get bringupStateStream => _bringup.stream;

  final _bringup = StreamController<PlaybackBringupState>.broadcast();

  @override
  Future<void> playItems(
    List<dynamic> items, {
    int startIndex = 0,
    Duration startPosition = Duration.zero,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? mediaSourceId,
    bool audioSelectionExplicit = false,
    bool subtitleSelectionExplicit = false,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
    bool autoPlay = true,
    bool carryTrackSelections = false,
  }) async {
    final id = (items.first as AggregatedItem).id;
    played.add(id);
    _bringup
      ..add(
        PlaybackBringupState(
          phase: PlaybackBringupPhase.opening,
          sessionToken: played.length,
          itemId: id,
        ),
      )
      ..add(
        PlaybackBringupState(
          phase: PlaybackBringupPhase.ready,
          sessionToken: played.length,
          itemId: id,
        ),
      );
    state.setPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauses += 1;
    state.setPlaying(false);
  }

  @override
  Future<void> resume() async {
    resumes += 1;
    state.setPlaying(true);
  }

  @override
  Future<void> stop({bool userInitiated = true}) async {}
}

GuideChannel _guide(String id, String name) {
  return GuideChannel(
    id: id,
    name: name,
    rawData: {directIptvMarker: true, 'Id': id, 'Name': name},
  );
}

DirectIptvSource _source(String id, String name) {
  return DirectIptvSource(
    id: id,
    name: name,
    kind: DirectIptvKind.m3u,
    baseUrl: 'https://$id.example/playlist.m3u',
    epgPath: '-',
  );
}

DirectChannel _channel(String sourceId, String name, String tvgId) {
  return DirectChannel(
    id: 'direct:$sourceId:$tvgId',
    sourceId: sourceId,
    name: name,
    streamUrl: 'https://$sourceId.example/$tvgId.ts',
    tvgId: tvgId,
  );
}

void main() {
  late _Manager manager;
  late DirectIptvCatalog catalog;

  setUp(() async {
    PlatformDetection.setTvMode(true);
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final prefs = await SharedPreferences.getInstance();
    final primary = _source('a', 'Mo Fin');
    final backup = _source('b', 'Backup');
    await prefs.setString(
      DirectIptvCatalog.prefsKey,
      jsonEncode([primary.toJson(), backup.toJson()]),
    );
    final snapshots = MemoryDirectIptvSnapshotStore();
    final fetched = DateTime.utc(2026, 11, 18);
    await snapshots.write(
      DirectIptvSnapshot(
        sourceId: 'a',
        fetchedAt: fetched,
        channels: [_channel('a', 'CNN', 'cnn'), _channel('a', 'ESPN', 'espn')],
        programs: const [],
      ),
    );
    await snapshots.write(
      DirectIptvSnapshot(
        sourceId: 'b',
        fetchedAt: fetched,
        channels: [_channel('b', 'CNN', 'cnn')],
        programs: const [],
      ),
    );
    catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: _Transport(),
      store: snapshots,
    );
    await catalog.ensureLoaded();

    final liveTv = _LiveTvApi();
    when(
      () => liveTv.getGuide(
        channelIds: any(named: 'channelIds'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async => const <String, dynamic>{'Items': []});
    when(liveTv.getTimers).thenAnswer((_) async => const <String, dynamic>{});
    final client = _Client();
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => client.userId).thenReturn('alice');
    when(() => client.accessToken).thenReturn('');
    when(() => client.liveTvApi).thenReturn(liveTv);

    manager = _Manager(_Backend());
    GetIt.instance
      ..registerSingleton<PlaybackManager>(manager)
      ..registerSingleton<UserPreferences>(UserPreferences(store))
      ..registerSingleton<MediaServerClient>(client)
      ..registerSingleton<DirectIptvCatalog>(catalog)
      ..registerSingleton<ScreensaverController>(_Screensaver())
      ..registerSingleton<PipService>(PipService())
      ..registerSingleton<LogService>(_Log());
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    manager.dispose();
    catalog.dispose();
    await GetIt.instance.reset();
  });

  Future<void> pumpPlayer(
    WidgetTester tester,
    List<GuideChannel> channels,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: LiveTvPlayerScreen(channels: channels, startIndex: 0),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> keyDown(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.pump();
  }

  Future<void> keyRepeat(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyRepeatEvent(key);
    await tester.pump();
  }

  Future<void> keyUp(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyUpEvent(key);
    await tester.pump();
  }

  testWidgets('left and right still change the channel, not the feed', (
    tester,
  ) async {
    await pumpPlayer(tester, [
      _guide('direct:a:cnn', 'CNN'),
      _guide('direct:a:espn', 'ESPN'),
    ]);
    expect(manager.played, ['direct:a:cnn']);
    expect(find.text('Switch feed (2)'), findsOneWidget);

    // Strip closed: Left/Right must not leave CNN or hop to the other feed.
    await keyDown(tester, LogicalKeyboardKey.arrowRight);
    await keyUp(tester, LogicalKeyboardKey.arrowRight);
    expect(manager.played, ['direct:a:cnn']);

    await keyDown(tester, LogicalKeyboardKey.arrowUp);
    await keyUp(tester, LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.text('Left and right change channel'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'DirectChannelStrip',
    );
    expect(find.text('CNN'), findsOneWidget);

    await keyDown(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('ESPN'), findsOneWidget);
    await keyRepeat(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('CNN'), findsOneWidget);
    expect(find.text('ESPN'), findsNothing);
    await keyUp(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('CNN'), findsOneWidget);
    expect(manager.played, ['direct:a:cnn']);

    await keyDown(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('ESPN'), findsOneWidget);
    await keyUp(tester, LogicalKeyboardKey.arrowRight);
    await keyDown(tester, LogicalKeyboardKey.select);
    await keyUp(tester, LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(manager.played, ['direct:a:cnn', 'direct:a:espn']);
    expect(manager.played, isNot(contains('direct:b:cnn')));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('down then right reaches Switch feed and select cycles it', (
    tester,
  ) async {
    await pumpPlayer(tester, [_guide('direct:a:cnn', 'CNN')]);
    expect(find.text('Switch feed (2)'), findsOneWidget);
    expect(manager.played, ['direct:a:cnn']);

    await keyDown(tester, LogicalKeyboardKey.arrowDown);
    await keyUp(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'LiveTvPlayPause');

    await keyDown(tester, LogicalKeyboardKey.arrowRight);
    await keyUp(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'LiveTvSwitchFeed');

    await keyDown(tester, LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Backup'), findsOneWidget);
    expect(manager.played, ['direct:a:cnn', 'direct:b:cnn']);

    await keyRepeat(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await keyRepeat(tester, LogicalKeyboardKey.select);
    await keyUp(tester, LogicalKeyboardKey.select);
    expect(manager.played, ['direct:a:cnn', 'direct:b:cnn']);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(directFeedChoiceKey('alice'));
    expect(stored, contains('tvg:cnn'));
    expect(stored, contains('direct:b:cnn'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('menu lists feeds with the current one checked', (tester) async {
    await pumpPlayer(tester, [_guide('direct:a:cnn', 'CNN')]);
    expect(manager.played, ['direct:a:cnn']);

    await keyDown(tester, LogicalKeyboardKey.contextMenu);
    await keyUp(tester, LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(find.text('Feeds'), findsOneWidget);
    final check = find.byIcon(Icons.check);
    expect(check, findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(of: check, matching: find.byType(Row)),
        matching: find.text('Mo Fin'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);

    await keyDown(tester, LogicalKeyboardKey.arrowDown);
    await keyUp(tester, LogicalKeyboardKey.arrowDown);
    await keyDown(tester, LogicalKeyboardKey.select);
    await keyUp(tester, LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Feeds'), findsNothing);
    expect(find.text('Backup'), findsOneWidget);
    expect(manager.played, ['direct:a:cnn', 'direct:b:cnn']);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(directFeedChoiceKey('alice')),
      contains('direct:b:cnn'),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a short OK pauses and a repeat does not resume or switch', (
    tester,
  ) async {
    await pumpPlayer(tester, [_guide('direct:a:cnn', 'CNN')]);
    expect(manager.state.isPlaying, isTrue);
    expect(manager.played, ['direct:a:cnn']);

    await keyDown(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    expect(manager.pauses, 1);
    expect(manager.state.isPlaying, isFalse);

    await keyRepeat(tester, LogicalKeyboardKey.select);
    await keyUp(tester, LogicalKeyboardKey.select);
    expect(manager.pauses, 1);
    expect(manager.resumes, 0);
    expect(manager.state.isPlaying, isFalse);
    expect(manager.played, ['direct:a:cnn']);

    await keyDown(tester, LogicalKeyboardKey.select);
    await keyUp(tester, LogicalKeyboardKey.select);
    expect(manager.resumes, 1);
    expect(manager.state.isPlaying, isTrue);
    expect(manager.played, ['direct:a:cnn']);

    await tester.pumpWidget(const SizedBox());
  });
}
