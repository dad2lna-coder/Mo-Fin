import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/games/games_hub_screen.dart';
import 'package:moonfin/ui/widgets/left_sidebar.dart';
import 'package:moonfin/ui/widgets/top_toolbar.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'bottom_nav/bottom_nav_fakes.dart';

void main() {
  late UserPreferences prefs;

  setUp(() async {
    final setup = await setUpBottomNav();
    prefs = setup.prefs;
    PlatformDetection.debugPhoneWebChrome = true;
  });

  tearDown(() async {
    PlatformDetection.debugPhoneWebChrome = null;
    await tearDownBottomNav();
  });

  testWidgets('left navbar does not cover the page until the drawer opens', (
    tester,
  ) async {
    await _pumpChrome(tester, prefs, NavbarPosition.left);
    final center = _center(tester);

    expect(_covers(tester, center), isFalse);
    expect(find.byKey(LeftSidebar.scrimInterceptorKey), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byKey(LeftSidebar.scrimInterceptorKey), findsOneWidget);
    expect(find.byKey(LeftSidebar.panelInterceptorKey), findsOneWidget);
    expect(
      tester
          .getRect(find.byKey(LeftSidebar.scrimInterceptorKey))
          .contains(center),
      isTrue,
    );

    await tester.tapAt(const Offset(340, 700));
    await tester.pumpAndSettle();

    expect(find.byKey(LeftSidebar.scrimInterceptorKey), findsNothing);
    expect(_covers(tester, center), isFalse);
  });

  testWidgets('top navbar intercepts only the toolbar band', (tester) async {
    await _pumpChrome(tester, prefs, NavbarPosition.top);
    final center = _center(tester);

    expect(_covers(tester, center), isFalse);
    expect(find.byType(PointerInterceptor), findsOneWidget);
    final rect = tester.getRect(find.byType(PointerInterceptor));
    final toolbarHeight = TopToolbar.heightFor(
      tester.element(find.byType(TopToolbar)),
    );
    expect(rect.top, 0);
    expect(rect.height, lessThanOrEqualTo(toolbarHeight + 1));
    expect(rect.bottom, lessThan(center.dy));
  });

  testWidgets('Games hub keeps the page clear under a collapsed left drawer', (
    tester,
  ) async {
    await prefs.set(UserPreferences.navbarPosition, NavbarPosition.left);
    usePhoneView(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GamesHubScreen(),
      ),
    );
    await tester.pumpAndSettle();
    final center = _center(tester);

    expect(find.text('Install ROM Manager to see games here'), findsOneWidget);
    expect(_covers(tester, center), isFalse);
    expect(find.byKey(LeftSidebar.scrimInterceptorKey), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byKey(LeftSidebar.scrimInterceptorKey), findsOneWidget);
    expect(find.byKey(LeftSidebar.panelInterceptorKey), findsOneWidget);

    await tester.tapAt(const Offset(340, 700));
    await tester.pumpAndSettle();
    expect(find.byKey(LeftSidebar.scrimInterceptorKey), findsNothing);
    expect(_covers(tester, center), isFalse);
  });
}

Future<void> _pumpChrome(
  WidgetTester tester,
  UserPreferences prefs,
  NavbarPosition position,
) async {
  await prefs.set(UserPreferences.navbarPosition, position);
  usePhoneView(tester);
  await tester.pumpWidget(bottomNavApp(child: const SizedBox.expand()));
  await tester.pumpAndSettle();
}

Offset _center(WidgetTester tester) {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  return Offset(size.width / 2, size.height / 2);
}

bool _covers(WidgetTester tester, Offset point) {
  for (final element in find.byType(PointerInterceptor).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      continue;
    }
    final rect = render.localToGlobal(Offset.zero) & render.size;
    if (rect.contains(point)) return true;
  }
  return false;
}
