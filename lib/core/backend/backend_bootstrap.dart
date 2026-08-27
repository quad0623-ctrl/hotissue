import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../config/app_config.dart';

/// 부팅 결과. 어느 백엔드로 떴는지와 익명 식별자를 담는다.
class BackendSetup {
  const BackendSetup({required this.mode, required this.anonId});

  final BackendMode mode;

  /// 이 브라우저의 익명 식별자.
  /// Supabase 모드에서는 익명 세션 uid, 그 외에는 로컬 생성 UUID.
  final String anonId;
}

/// 앱 시작 시 백엔드를 준비한다.
///
/// **계정 제도가 없으므로 로그인 화면도 없다.** 앱이 뜨는 순간 익명 신원이 생기고,
/// 사용자는 자기가 "로그인"했다는 사실조차 모른다. 이 식별자는 셋에만 쓴다:
/// 자기 글 구분 · 1인 1추천 · 도배 차단.
///
/// 어느 단계에서 실패하든 목 백엔드로 떨어진다.
/// 백엔드가 없다고 화면을 못 보는 상황을 만들지 않기 위해서다.
abstract final class BackendBootstrap {
  static const _anonKey = 'hotissue.anon_id';

  static Future<BackendSetup> init() async {
    final mode = AppConfig.preferredMode;

    if (mode == BackendMode.supabase) {
      final uid = await _initSupabase();
      if (uid != null) {
        return BackendSetup(mode: BackendMode.supabase, anonId: uid);
      }
      debugPrint('[hotissue] Supabase 실패 → 수집기/목으로 폴백합니다.');
    }

    final anonId = await _localAnonId();

    // 여기 왔다는 건 Supabase 를 안 쓰거나 초기화가 실패했다는 뜻이다.
    // 수집기 주소가 있으면 그쪽으로 간다.
    if (AppConfig.hasCollector) {
      debugPrint('[hotissue] 수집기 백엔드: ${AppConfig.collectorUrl}');
      return BackendSetup(mode: BackendMode.collector, anonId: anonId);
    }

    debugPrint('[hotissue] 목 백엔드로 실행합니다.');
    return BackendSetup(mode: BackendMode.mock, anonId: anonId);
  }

  static Future<String?> _initSupabase() async {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseKey,
        debug: kDebugMode,
      );

      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        await auth.signInAnonymously();
      }

      final uid = auth.currentUser?.id;
      debugPrint('[hotissue] Supabase 연결 완료 (익명 세션 $uid).');
      return uid;
    } catch (error, stack) {
      debugPrint('[hotissue] Supabase 초기화 실패: $error');
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  /// 브라우저 저장소에 한 번 만들어두고 계속 쓰는 익명 ID.
  ///
  /// 저장소를 비우면 사라진다 — 그게 익명 서비스의 올바른 동작이다.
  /// 기기 간 동기화는 불가능하고, 그건 계정을 두지 않기로 한 대가다.
  static Future<String> _localAnonId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_anonKey);
      if (existing != null && existing.isNotEmpty) return existing;

      final created = _randomId();
      await prefs.setString(_anonKey, created);
      return created;
    } catch (error) {
      // 저장소를 못 쓰는 환경(시크릿 모드 등)에서도 앱은 떠야 한다.
      debugPrint('[hotissue] 익명 ID 저장 실패, 세션 한정 ID 를 씁니다: $error');
      return _randomId();
    }
  }

  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
