import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/crashlytics.dart';
import 'package:lichess_mobile/src/db/database.dart';
import 'package:lichess_mobile/src/model/auth/auth_session.dart';
import 'package:lichess_mobile/src/model/common/service/sound_service.dart';
import 'package:lichess_mobile/src/model/notifications/notification_service.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/utils/connectivity.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import './fake_crashlytics.dart';
import './model/common/service/fake_sound_service.dart';
import 'binding.dart';
import 'model/notifications/fake_notification_display.dart';
import 'network/fake_http_client_factory.dart';
import 'network/fake_websocket_channel.dart';
import 'utils/fake_connectivity.dart';

/// A mock client that always returns a 200 empty response.
final testContainerMockClient = MockClient((request) async {
  return http.Response('', 200);
});

const shouldLog = false;

/// Returns a [ProviderContainer] with the [httpClientFactoryProvider] configured
/// with the given [mockClient].
Future<ProviderContainer> lichessClientContainer(MockClient mockClient) async {
  return makeContainer(
    overrides: [
      httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => mockClient);
      }),
    ],
  );
}

/// Returns a [ProviderContainer] with default mocks, ready for testing.
Future<ProviderContainer> makeContainer({
  List<Override>? overrides,
  AuthSessionState? userSession,
}) async {
  final binding = TestLichessBinding.ensureInitialized();

  FlutterSecureStorage.setMockInitialValues({
    kSRIStorageKey: 'test',
  });

  await binding.preloadData(userSession);

  Logger.root.onRecord.listen((record) {
    if (shouldLog && record.level >= Level.FINE) {
      final time = DateFormat.Hms().format(record.time);
      debugPrint(
        '${record.level.name} at $time [${record.loggerName}] ${record.message}${record.error != null ? '\n${record.error}' : ''}',
      );
    }
  });

  final container = ProviderContainer(
    overrides: [
      connectivityPluginProvider.overrideWith((_) {
        return FakeConnectivity();
      }),
      notificationDisplayProvider.overrideWith((ref) {
        return FakeNotificationDisplay();
      }),
      databaseProvider.overrideWith((ref) async {
        final db =
            await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
        ref.onDispose(db.close);
        return db;
      }),
      webSocketChannelFactoryProvider.overrideWith((ref) {
        return FakeWebSocketChannelFactory(() => FakeWebSocketChannel());
      }),
      socketPoolProvider.overrideWith((ref) {
        final pool = SocketPool(ref);
        ref.onDispose(pool.dispose);
        return pool;
      }),
      httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => testContainerMockClient);
      }),
      crashlyticsProvider.overrideWithValue(FakeCrashlytics()),
      soundServiceProvider.overrideWithValue(FakeSoundService()),
      ...overrides ?? [],
    ],
  );

  addTearDown(binding.reset);
  addTearDown(container.dispose);

  return container;
}
