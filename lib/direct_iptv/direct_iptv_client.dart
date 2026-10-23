import 'dart:convert';

import 'package:http/http.dart' as http;

class DirectIptvHttpResult {
  final int statusCode;
  final String body;

  const DirectIptvHttpResult(this.statusCode, this.body);
}

/// A response whose body is still a stream. [statusCode] is known before
/// the body is read, so a 403 or 429 can be drained instead of buffered.
class DirectIptvByteSource {
  final int statusCode;
  final Stream<List<int>> bytes;

  /// The URL after redirects. Relative HLS renditions have to be resolved
  /// against this, not the URL that was requested.
  final Uri finalUrl;

  const DirectIptvByteSource({
    required this.statusCode,
    required this.bytes,
    required this.finalUrl,
  });
}

/// Small GET wrapper so tests can answer without the network.
abstract class DirectIptvTransport {
  Future<DirectIptvHttpResult> get(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 20),
  });

  /// Default reads [get] and chunks the body, which is enough for tests.
  /// The HTTP client overrides this and does not buffer first.
  Future<DirectIptvByteSource> open(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final result = await get(url, headers, timeout: timeout);
    return DirectIptvByteSource(
      statusCode: result.statusCode,
      bytes: Stream<List<int>>.value(utf8.encode(result.body)),
      finalUrl: url,
    );
  }

  /// POST, DELETE, and other verbs. [body] is written as a string.
  /// Fake transports used by playlist tests can ignore this.
  Future<DirectIptvHttpResult> send(
    String method,
    Uri url,
    Map<String, String> headers, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) {
    if (method.toUpperCase() == 'GET' && body == null) {
      return get(url, headers, timeout: timeout);
    }
    throw UnsupportedError('DirectIptvTransport.$method');
  }

  /// Response headers of a short GET. The body is dropped. The default
  /// answers nothing so playlist tests never open a stream.
  Future<Map<String, String>> peekHeaders(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 8),
  }) async => const {};
}

class HttpDirectIptvTransport implements DirectIptvTransport {
  final http.Client _client;

  HttpDirectIptvTransport([http.Client? client])
    : _client = client ?? http.Client();

  @override
  Future<DirectIptvHttpResult> get(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final response = await _client.get(url, headers: headers).timeout(timeout);
    return DirectIptvHttpResult(response.statusCode, response.body);
  }

  @override
  Future<DirectIptvByteSource> open(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final request = http.Request('GET', url)..headers.addAll(headers);
    final streamed = await _client.send(request).timeout(timeout);
    final Uri finalUrl;
    final Object response = streamed;
    if (response is http.BaseResponseWithUrl) {
      finalUrl = response.url;
    } else {
      finalUrl = streamed.request?.url ?? url;
    }
    return DirectIptvByteSource(
      statusCode: streamed.statusCode,
      bytes: streamed.stream,
      finalUrl: finalUrl,
    );
  }

  @override
  Future<DirectIptvHttpResult> send(
    String method,
    Uri url,
    Map<String, String> headers, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = http.Request(method, url)..headers.addAll(headers);
    if (body != null) {
      request.body = body is String ? body : body.toString();
      request.headers.putIfAbsent(
        'Content-Type',
        () => 'application/json; charset=utf-8',
      );
    }
    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    return DirectIptvHttpResult(response.statusCode, response.body);
  }

  @override
  Future<Map<String, String>> peekHeaders(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final request = http.Request('GET', url)..headers.addAll(headers);
    request.headers.putIfAbsent('Range', () => 'bytes=0-1023');
    final streamed = await _client.send(request).timeout(timeout);
    final flat = <String, String>{
      for (final entry in streamed.headers.entries) entry.key: entry.value,
    };
    // Headers are already in. Cancel before a live stream can fill the buffer.
    try {
      final subscription = streamed.stream.listen((_) {}, onError: (_) {});
      await subscription.cancel();
    } catch (_) {}
    return flat;
  }
}
