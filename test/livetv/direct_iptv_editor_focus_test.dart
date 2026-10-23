import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/direct_iptv/direct_iptv_catalog.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:moonfin/direct_iptv/snapshot_store.dart';
import 'package:moonfin/ui/screens/livetv/direct_iptv_settings_screen.dart';
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
}
