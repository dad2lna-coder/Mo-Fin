import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:moonfin/ui/screens/livetv/direct_guide_source.dart';

DirectIptvSource _source({
  required String id,
  required String name,
  required DirectIptvKind kind,
  bool enabled = true,
}) {
  return DirectIptvSource(
    id: id,
    name: name,
    kind: kind,
    baseUrl: 'http://example.test',
    enabled: enabled,
  );
}

void main() {
  final dispatcharr = _source(
    id: 'dispatch',
    name: 'Dispatcharr',
    kind: DirectIptvKind.dispatcharr,
  );
  final moFin = _source(id: 'mofin', name: 'Mo Fin', kind: DirectIptvKind.m3u);
  final other = _source(id: 'other', name: 'News', kind: DirectIptvKind.m3u);

  test('a saved enabled source wins over Mo Fin and Dispatcharr', () {
    expect(
      chooseDefaultDirectSource(
        sources: [dispatcharr, moFin, other],
        savedId: 'other',
      ),
      'other',
    );
  });

  test('a missing or disabled saved source falls through to Mo Fin', () {
    final disabledMoFin = _source(
      id: 'mofin-off',
      name: 'Mo Fin',
      kind: DirectIptvKind.m3u,
      enabled: false,
    );
    expect(
      chooseDefaultDirectSource(
        sources: [dispatcharr, disabledMoFin, moFin],
        savedId: 'gone',
      ),
      'mofin',
    );
    expect(
      chooseDefaultDirectSource(
        sources: [dispatcharr, moFin],
        savedId: 'dispatch-off',
      ),
      'mofin',
    );
    final disabledSaved = _source(
      id: 'other',
      name: 'News',
      kind: DirectIptvKind.m3u,
      enabled: false,
    );
    expect(
      chooseDefaultDirectSource(
        sources: [dispatcharr, disabledSaved, moFin],
        savedId: 'other',
      ),
      'mofin',
    );
  });

  test(
    'Mo Fin is preferred to an earlier Dispatcharr when nothing is saved',
    () {
      expect(
        chooseDefaultDirectSource(sources: [dispatcharr, other, moFin]),
        'mofin',
      );
      expect(
        chooseDefaultDirectSource(
          sources: [dispatcharr, other, moFin],
          savedId: '  ',
        ),
        'mofin',
      );
    },
  );

  test('only an enabled M3U named Mo Fin is the preferred source', () {
    final namedDispatcharr = _source(
      id: 'named',
      name: 'Mo Fin',
      kind: DirectIptvKind.dispatcharr,
    );
    final namedPluto = _source(
      id: 'pluto',
      name: 'Mo Fin',
      kind: DirectIptvKind.pluto,
    );
    final disabled = _source(
      id: 'off',
      name: 'Mo Fin',
      kind: DirectIptvKind.m3u,
      enabled: false,
    );
    expect(
      chooseDefaultDirectSource(
        sources: [other, namedDispatcharr, namedPluto, disabled],
      ),
      'other',
    );
  });

  test('the first enabled source is the last resort', () {
    expect(
      chooseDefaultDirectSource(sources: [dispatcharr, other]),
      'dispatch',
    );
    expect(
      chooseDefaultDirectSource(sources: const [], savedId: 'mofin'),
      isNull,
    );
  });
}
