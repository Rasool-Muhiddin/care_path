@TestOn('browser')
library;

import 'package:axon/core/update/app_update_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// على الويب كان Platform.isAndroid يرمي UnsupportedError فتتعطل شاشة
/// البداية (splash) قبل الدخول. يُشغَّل بـ: flutter test --platform chrome test/web
void main() {
  test('update check is skipped on web without throwing', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(appUpdateProvider.future), isNull);
  });
}
