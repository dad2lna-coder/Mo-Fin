import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/direct_iptv_client.dart';
import 'package:moonfin/direct_iptv/direct_iptv_recordings.dart';
import 'package:moonfin/direct_iptv/models.dart';

class _Call {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;

  const _Call(this.method, this.url, this.headers, this.body);
}

class _Transport extends DirectIptvTransport {
  _Transport(this.handler);

  final DirectIptvHttpResult Function(_Call call) handler;
  final calls = <_Call>[];

  @override
  Future<DirectIptvHttpResult> get(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 20),
  }) {
    return send('GET', url, headers, timeout: timeout);
  }

  @override
  Future<DirectIptvHttpResult> send(
    String method,
    Uri url,
    Map<String, String> headers, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final call = _Call(method, url, headers, body?.toString());
    calls.add(call);
    return handler(call);
  }
}

DirectIptvSource _source({String baseUrl = 'http://dispatch.test'}) {
  return DirectIptvSource(
    id: 'src',
    name: 'Home',
    kind: DirectIptvKind.dispatcharr,
    baseUrl: baseUrl,
    token: 'tok',
  );
}

DirectChannel _channel(String tvgId) => DirectChannel(
  id: 'direct:src:$tvgId',
  sourceId: 'src',
  name: 'News',
  streamUrl: 'http://dispatch.test/news.ts',
  tvgId: tvgId,
);

DirectProgram _program(DateTime start, DateTime end) => DirectProgram(
  id: 'p',
  channelKey: 'direct:src:news',
  title: 'Nightly',
  start: start,
  end: end,
);

void main() {
  final start = DateTime.utc(2026, 10, 22, 20);
  final end = DateTime.utc(2026, 10, 22, 21);

  test('schedule posts tvg id, title, and ISO times under rec/', () async {
    final transport = _Transport(
      (call) => const DirectIptvHttpResult(201, '{"id":"job-1"}'),
    );
    final client = DirectIptvRecordings(transport: transport);

    final created = await client.schedule(
      source: _source(baseUrl: 'http://dispatch.test/'),
      tvgId: 'news',
      title: 'Nightly',
      start: start,
      end: end,
    );

    final call = transport.calls.single;
    expect(call.method, 'POST');
    expect(call.url.toString(), 'http://dispatch.test/rec/schedule');
    expect(call.headers['Authorization'], 'Bearer tok');
    expect(call.headers['Content-Type'], 'application/json');
    final body = jsonDecode(call.body!) as Map<String, dynamic>;
    expect(body['tvg_id'], 'news');
    expect(body['title'], 'Nightly');
    expect(body['start'], start.toIso8601String());
    expect(body['end'], end.toIso8601String());
    expect(created.id, 'job-1');
    expect(created.status, 'scheduled');
    expect(created.tvgId, 'news');
  });

  test('list reads rec/list and delete calls rec/<id>', () async {
    final body = jsonEncode({
      'recordings': [
        {
          'id': 'job-1',
          'tvg_id': 'news',
          'title': 'Nightly',
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
          'status': 'recording',
        },
        {
          'id': 'old',
          'tvg_id': 'news',
          'title': 'Earlier',
          'start': start.subtract(const Duration(hours: 3)).toIso8601String(),
          'end': start.subtract(const Duration(hours: 2)).toIso8601String(),
          'status': 'completed',
        },
      ],
    });
    final transport = _Transport((call) {
      if (call.method == 'GET') return DirectIptvHttpResult(200, body);
      return const DirectIptvHttpResult(204, '');
    });
    final client = DirectIptvRecordings(transport: transport);
    final source = _source();

    final items = await client.list(source);
    expect(
      transport.calls.single.url.toString(),
      'http://dispatch.test/rec/list',
    );
    expect(items.map((item) => item.id), ['job-1', 'old']);
    expect(items.first.marksGuide, isTrue);
    expect(items.last.marksGuide, isFalse);
    expect(items.first.status, 'recording');

    final channel = _channel('news');
    final program = _program(start, end);
    expect(
      directRecordingFor(
        recordings: items,
        channel: channel,
        program: program,
      )?.id,
      'job-1',
    );
    expect(
      directRecordingFor(
        recordings: items,
        channel: channel,
        program: _program(
          start.subtract(const Duration(hours: 3)),
          start.subtract(const Duration(hours: 2)),
        ),
      ),
      isNull,
    );

    await client.cancel(source, 'job/1');
    final deleted = transport.calls.last;
    expect(deleted.method, 'DELETE');
    expect(deleted.url.toString(), 'http://dispatch.test/rec/job%2F1');
  });

  test('a missing recordings API fails quietly', () async {
    final transport = _Transport(
      (call) => const DirectIptvHttpResult(404, 'not found'),
    );
    final client = DirectIptvRecordings(transport: transport);

    await expectLater(
      client.schedule(
        source: _source(),
        tvgId: 'news',
        title: 'Nightly',
        start: start,
        end: end,
      ),
      throwsA(
        isA<DirectIptvRecordingsException>().having(
          (error) => error.message,
          'message',
          directRecordingsMissingMessage,
        ),
      ),
    );
    expect(transport.calls.single.url.path, '/rec/schedule');

    await expectLater(
      client.list(_source()),
      throwsA(
        isA<DirectIptvRecordingsException>().having(
          (error) => error.toString(),
          'string',
          directRecordingsMissingMessage,
        ),
      ),
    );
  });

  test(
    'scheduled and in-progress programs take a dot, finished ones do not',
    () {
      final now = DateTime.utc(2026, 10, 22, 20, 30);
      final parsed = parseDirectRecordings(
        jsonEncode([
          {
            'id': 7,
            'tvgId': 'news',
            'name': 'Nightly',
            'start': start.toIso8601String(),
            'stop': end.toIso8601String(),
            'state': 'in-progress',
          },
          {
            'tvg_id': 'news',
            'title': 'Later',
            'start_time': end.toIso8601String(),
            'end_time': end.add(const Duration(hours: 1)).toIso8601String(),
          },
        ]),
        now: now,
      );
      expect(parsed[0].id, '7');
      expect(parsed[0].status, 'recording');
      expect(parsed[1].status, 'scheduled');
      expect(parsed[0].marksGuide, isTrue);
      expect(parsed[1].marksGuide, isTrue);

      final off = start.add(const Duration(minutes: 5));
      expect(
        directRecordingFor(
          recordings: parsed,
          channel: _channel('news'),
          program: _program(off, end.add(const Duration(minutes: 5))),
        ),
        isNull,
      );
    },
  );
}
