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

const _session = {
  'Authorization':
      'MediaBrowser Client="Moonfin", Device="Phone", DeviceId="abc", Version="1", Token="session"',
};

DirectIptvRecordings _client(_Transport transport) {
  return DirectIptvRecordings(
    transport: transport,
    baseUrl: 'http://jellyfin.test',
    sessionHeaders: _session,
  );
}

DirectChannel _channel(String tvgId) => DirectChannel(
  id: 'direct:src:$tvgId',
  sourceId: 'src',
  name: 'News',
  streamUrl: 'http://example.test/news.ts',
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

  test('schedule posts to Moonbase with the session, not a source key', () async {
    final transport = _Transport(
      (call) => const DirectIptvHttpResult(201, '{"id":"job-1"}'),
    );
    final client = _client(transport);

    final created = await client.schedule(
      tvgId: 'news',
      title: 'Nightly',
      start: start,
      end: end,
      streamUrl: 'http://example.test/news.ts',
      recUrl: 'http://example.test/rec.ts',
    );

    final call = transport.calls.single;
    expect(call.method, 'POST');
    expect(
      call.url.toString(),
      'http://jellyfin.test/Moonfin/LiveTv/Direct/Recordings',
    );
    expect(call.headers['Authorization'], _session['Authorization']);
    expect(call.headers['Authorization'], isNot(contains('Bearer')));
    expect(call.headers.containsKey('X-Mofin-Key'), isFalse);
    expect(call.headers['Content-Type'], 'application/json');
    final body = jsonDecode(call.body!) as Map<String, dynamic>;
    expect(body['tvgId'], 'news');
    expect(body['title'], 'Nightly');
    expect(body['start'], start.toIso8601String());
    expect(body['end'], end.toIso8601String());
    expect(body['streamUrl'], 'http://example.test/news.ts');
    expect(body['recUrl'], 'http://example.test/rec.ts');
    expect(body.containsKey('token'), isFalse);
    expect(created.id, 'job-1');
    expect(created.status, 'scheduled');
    expect(created.tvgId, 'news');
  });

  test('list and delete use the Moonbase recordings route', () async {
    final body = jsonEncode({
      'recordings': [
        {
          'id': 'job-1',
          'tvgId': 'news',
          'title': 'Nightly',
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
          'status': 'recording',
        },
        {
          'id': 'old',
          'tvgId': 'news',
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
    final client = _client(transport);

    final items = await client.list();
    expect(
      transport.calls.single.url.toString(),
      'http://jellyfin.test/Moonfin/LiveTv/Direct/Recordings',
    );
    expect(transport.calls.single.headers['Authorization'], contains('session'));
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

    await client.cancel('job/1');
    final deleted = transport.calls.last;
    expect(deleted.method, 'DELETE');
    expect(
      deleted.url.toString(),
      'http://jellyfin.test/Moonfin/LiveTv/Direct/Recordings/job%2F1',
    );
    expect(deleted.headers.containsKey('X-Mofin-Key'), isFalse);
  });

  test('a missing Moonbase recordings API fails without asking for a key', () async {
    final transport = _Transport(
      (call) => const DirectIptvHttpResult(404, 'not found'),
    );
    final client = _client(transport);

    await expectLater(
      client.schedule(
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
    expect(transport.calls.single.url.path, '/Moonfin/LiveTv/Direct/Recordings');

    await expectLater(
      client.list(),
      throwsA(
        isA<DirectIptvRecordingsException>().having(
          (error) => error.toString(),
          'string',
          directRecordingsMissingMessage,
        ),
      ),
    );
  });

  test('a forbidden session says recording is not allowed', () async {
    final transport = _Transport(
      (call) => const DirectIptvHttpResult(403, ''),
    );
    final client = _client(transport);

    await expectLater(
      client.list(),
      throwsA(
        isA<DirectIptvRecordingsException>().having(
          (error) => error.message,
          'message',
          directRecordingsForbiddenMessage,
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
