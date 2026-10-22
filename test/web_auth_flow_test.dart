import 'dart:convert';
import 'dart:typed_data';

import 'package:axon/core/auth/auth_state.dart';
import 'package:axon/core/auth/token_storage.dart';
import 'package:axon/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// مسار مصادقة الويب (PWA) على الـ VM: kIsWeb ثابت هنا، فنفعّل مسار
/// الكوكي بـ TokenStorage.debugUseRefreshCookie. الخادم وهمي (adapter):
/// يتحقق أن الطلبات تحمل X-Axon-Client ولا ترسل/تتوقع refresh في الجسم.
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.routes);

  /// path -> (status, body)
  final Map<String, (int, Map<String, dynamic>)> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final route = routes[options.uri.path] ?? (404, {'detail': 'not found'});
    return ResponseBody.fromString(jsonEncode(route.$2), route.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}

  List<String> get paths => requests.map((r) => r.uri.path).toList();
  RequestOptions last(String path) => requests.lastWhere((r) => r.uri.path == path);
}

const _me = {'id': 1, 'username': 'p', 'first_name': 'م', 'last_name': 'ر', 'role': 'patient'};

ProviderContainer _container(_FakeServer server) {
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWith((ref) {
      return ApiClient(onSessionExpired: () => ref.read(authStateProvider.notifier).logout())
        ..raw.httpClientAdapter = server;
    }),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<AuthStatus> _settled(ProviderContainer container) async {
  container.read(authStateProvider);
  for (var i = 0; i < 50; i++) {
    final s = container.read(authStateProvider);
    if (s is! AuthInitial && s is! AuthLoading) return s;
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(authStateProvider);
}

void main() {
  setUp(() async {
    TokenStorage.debugUseRefreshCookie = true;
    await TokenStorage.instance.clear();
  });
  tearDown(() async {
    await TokenStorage.instance.clear();
    TokenStorage.debugUseRefreshCookie = null;
  });

  test('page reload restores the session silently from the refresh cookie', () async {
    final server = _FakeServer({
      '/api/auth/refresh/': (200, {'access': 'acc-1'}),
      '/api/auth/me/': (200, _me),
    });
    final status = await _settled(_container(server));

    expect(status, isA<AuthAuthenticated>());
    expect(server.paths, ['/api/auth/refresh/', '/api/auth/me/']);
    final refresh = server.last('/api/auth/refresh/');
    expect(refresh.headers['X-Axon-Client'], 'web');
    expect(refresh.data, isNull, reason: 'refresh comes from the HttpOnly cookie, never the body');
    expect(server.last('/api/auth/me/').headers['Authorization'], 'Bearer acc-1');
    expect(await TokenStorage.instance.accessToken, 'acc-1');
  });

  test('no cookie session -> unauthenticated, without calling logout', () async {
    final server = _FakeServer({
      '/api/auth/refresh/': (401, {'detail': 'لا توجد جلسة.', 'code': 'token_not_valid'}),
    });
    expect(await _settled(_container(server)), isA<AuthUnauthenticated>());
    expect(server.paths, ['/api/auth/refresh/']);
  });

  test('server unreachable during restore -> offline with retry, not logged out', () async {
    final server = _FakeServer({'/api/auth/refresh/': (502, {'detail': 'bad gateway'})});
    expect(await _settled(_container(server)), isA<AuthOffline>());
  });

  test('login keeps the access token in memory only; logout posts no body', () async {
    final server = _FakeServer({
      '/api/auth/refresh/': (401, {'detail': 'x'}),
      '/api/auth/login/': (200, {'access': 'acc-2'}),
      '/api/auth/me/': (200, _me),
      '/api/auth/logout/': (200, {}),
    });
    final container = _container(server);
    await _settled(container);

    await container.read(authStateProvider.notifier).login(username: 'p', password: 'pw');
    expect(container.read(authStateProvider), isA<AuthAuthenticated>());
    expect(server.last('/api/auth/login/').headers['X-Axon-Client'], 'web');
    expect(await TokenStorage.instance.accessToken, 'acc-2');
    expect(await TokenStorage.instance.refreshToken, isNull);

    await container.read(authStateProvider.notifier).logout();
    final logout = server.last('/api/auth/logout/');
    expect(logout.data, isNull);
    expect(logout.headers['X-Axon-Client'], 'web');
    expect(await TokenStorage.instance.hasTokens, isFalse);
  });

  test('expired access token is refreshed via the cookie and the request retried', () async {
    var meCalls = 0;
    final server = _FakeServer({
      '/api/auth/refresh/': (200, {'access': 'acc-new'}),
    });
    final client = ApiClient(onSessionExpired: () {})..raw.httpClientAdapter = _MeOnce(server, () => meCalls++);
    await TokenStorage.instance.updateAccessToken('acc-old');

    final response = await client.raw.get('/auth/me/');
    expect(response.statusCode, 200);
    expect(meCalls, 2);
    expect(server.last('/api/auth/refresh/').data, isNull);
    expect(await TokenStorage.instance.accessToken, 'acc-new');
  });
}

/// /me يرد 401 أول مرة (access منتهٍ) ثم 200؛ الباقي للخادم الوهمي.
class _MeOnce implements HttpClientAdapter {
  _MeOnce(this.server, this.onMe);
  final _FakeServer server;
  final void Function() onMe;
  var _first = true;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (options.uri.path == '/api/auth/me/') {
      onMe();
      final status = _first ? 401 : 200;
      _first = false;
      return Future.value(ResponseBody.fromString(jsonEncode(status == 200 ? _me : {'detail': 'expired'}), status,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]}));
    }
    return server.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
