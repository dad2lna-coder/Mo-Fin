import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/direct_iptv/direct_iptv_catalog.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:moonfin/direct_iptv/snapshot_store.dart';
import 'package:moonfin/ui/screens/livetv/direct_iptv_settings_screen.dart';
import 'package:moonfin/ui/widgets/focus/dpad_focus_marker.dart';
import 'package:moonfin/ui/widgets/mofin_brand.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _addRows = [
  'Name',
  'Type',
  'Address',
  'Username',
  'Password',
  'Token',
  'M3U path',
  'EPG path',
  'Refresh every (minutes)',
  'Preferred subtitle language',
  'Preferred audio language',
  'Captions on by default',
  'Enabled',
  'Save',
];

Future<DirectIptvCatalog> _catalog({DirectIptvSource? existing}) async {
  SharedPreferences.setMockInitialValues({
    if (existing != null)
      DirectIptvCatalog.prefsKey: jsonEncode([existing.toJson()]),
  });
  final prefs = await SharedPreferences.getInstance();
  final catalog = DirectIptvCatalog(
    preferences: prefs,
    store: MemoryDirectIptvSnapshotStore(),
  );
  await catalog.ensureLoaded();
  await GetIt.instance.reset();
  GetIt.instance.registerSingleton<DirectIptvCatalog>(catalog);
  return catalog;
}

Future<void> _open(WidgetTester tester, DirectIptvSettingsScreen screen) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

Future<void> _down(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pump();
}

void main() {
  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('Down walks every Add source row and stops on Save', (
    tester,
  ) async {
    await _catalog();
    await _open(tester, const DirectIptvSettingsScreen(createOnOpen: true));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'iptv-row:Name');
    for (var i = 1; i < _addRows.length; i++) {
      await _down(tester);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'iptv-row:${_addRows[i]}',
        reason: 'after $i downs',
      );
    }
    await _down(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'iptv-row:Save');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'iptv-row:Enabled');
  });

  testWidgets('Edit source adds Remove after Save', (tester) async {
    await _catalog(
      existing: const DirectIptvSource(
        id: 'mofin',
        name: 'Mo Fin',
        kind: DirectIptvKind.m3u,
        baseUrl: 'https://dad2lna.duckdns.org:8443/mofin/free/',
      ),
    );
    await _open(tester, const DirectIptvSettingsScreen(editSourceId: 'mofin'));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'iptv-row:Name');
    for (var i = 0; i < _addRows.length; i++) {
      await _down(tester);
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-row:Remove source',
    );
    await _down(tester);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-row:Remove source',
    );
  });

  testWidgets('Down from a text field reaches Cancel and then Save', (
    tester,
  ) async {
    await _catalog();
    await _open(tester, const DirectIptvSettingsScreen(createOnOpen: true));

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'direct-iptv-text');
    await _down(tester);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-dialog:Cancel',
    );
    await _down(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'iptv-dialog:Save');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-dialog:Cancel',
    );
  });

  testWidgets('focused row shows an accent frame on light and dark', (
    tester,
  ) async {
    await _catalog();
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const DirectIptvSettingsScreen(createOnOpen: true),
        ),
      );
      await tester.pumpAndSettle();

      final frames = tester
          .widgetList<DpadFocusFrame>(find.byType(DpadFocusFrame))
          .toList();
      final focused = frames.where((frame) => frame.focused).toList();
      expect(focused, hasLength(1), reason: theme.brightness.name);

      final box = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byWidget(focused.single),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final border =
          (box.foregroundDecoration! as BoxDecoration).border! as Border;
      final accent = theme.colorScheme.primary;
      expect(border.top.color, accent);
      expect(border.top.width, greaterThanOrEqualTo(2));
      final fill = (box.decoration! as BoxDecoration).color!;
      expect(fill.a, greaterThan(0));

      final title = tester.element(find.text('Name').first);
      final text = DefaultTextStyle.of(title).style.color!;
      final surface = theme.colorScheme.surface;
      expect(_contrast(text, surface), greaterThan(3));
      // The check is not how focus is shown. Nothing is selected on Name.
      expect(
        find.descendant(
          of: find.byWidget(focused.single),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('a selected option keeps its check when focus moves', (
    tester,
  ) async {
    await _catalog();
    await _open(tester, const DirectIptvSettingsScreen(createOnOpen: true));
    await _down(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('Dispatcharr'), findsWidgets);
    await _down(tester);
    expect(find.byIcon(Icons.check), findsOneWidget);
    final checks = tester.widgetList<Icon>(find.byIcon(Icons.check));
    expect(checks.single.color, isNotNull);
  });

  testWidgets('dialog buttons take the same focus frame', (tester) async {
    await _catalog();
    await _open(tester, const DirectIptvSettingsScreen(createOnOpen: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    DpadFocusFrame frameFor(String label) {
      final text = find.text(label);
      final frame = find.ancestor(
        of: text,
        matching: find.byType(DpadFocusFrame),
      );
      return tester.widget<DpadFocusFrame>(frame.first);
    }

    expect(frameFor('Cancel').focused, isFalse);
    await _down(tester);
    expect(frameFor('Cancel').focused, isTrue);
    expect(frameFor('Save').focused, isFalse);
  });

  test('logo asset follows the background', () {
    expect(
      MoFinBrand.assetFor(wordmark: true, dark: true),
      'assets/icons/mofin_lockup_dark.svg',
    );
    expect(
      MoFinBrand.assetFor(wordmark: true, dark: false),
      'assets/icons/mofin_lockup_light.svg',
    );
    expect(
      MoFinBrand.assetFor(wordmark: false, dark: true),
      endsWith('mofin_mark_dark.svg'),
    );
    expect(
      MoFinBrand.assetFor(wordmark: false, dark: false),
      endsWith('mofin_mark_light.svg'),
    );
  });
}

double _contrast(Color a, Color b) {
  final hi = math.max(a.computeLuminance(), b.computeLuminance());
  final lo = math.min(a.computeLuminance(), b.computeLuminance());
  return (hi + 0.05) / (lo + 0.05);
}
