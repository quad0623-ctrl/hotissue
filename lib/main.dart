import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/backend/backend_bootstrap.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // 로그인 화면이 없다. 여기서 익명 신원까지 끝낸다.
  // 어느 단계에서 실패하든 목 백엔드로 떨어지므로 화면은 어떤 경우에도 보인다.
  final setup = await BackendBootstrap.init();

  runApp(
    ProviderScope(
      overrides: [backendSetupProvider.overrideWithValue(setup)],
      child: const HotIssueApp(),
    ),
  );
}
