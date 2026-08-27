import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:hotissue_collector/src/collector.dart';
import 'package:hotissue_collector/src/server.dart';
import 'package:hotissue_collector/src/source.dart';
import 'package:hotissue_collector/src/store.dart';

/// 핫이슈 수집기.
///
///   dart run bin/hotissue_collector.dart              # 수집 + 서빙
///   dart run bin/hotissue_collector.dart --once       # 한 번만 수집하고 종료
///   dart run bin/hotissue_collector.dart --port 9000
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8787')
    ..addOption('interval', abbr: 'i', defaultsTo: '120', help: '수집 주기(초)')
    ..addOption('state', defaultsTo: '.data/state.json')
    ..addFlag('once', negatable: false, help: '한 번만 수집하고 종료')
    ..addFlag('help', abbr: 'h', negatable: false);

  final opts = parser.parse(args);
  if (opts['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final port = int.parse(opts['port'] as String);
  final interval = Duration(seconds: int.parse(opts['interval'] as String));

  final store = Store(File(opts['state'] as String));
  await store.load();
  stdout.writeln('[수집기] 상태 복원: 이슈 ${store.issues.length}건');

  final collector = Collector(store: store);

  final feedCount = kOutlets.fold<int>(0, (n, o) => n + o.feeds.length);
  stdout.writeln('[수집기] 언론사 ${kOutlets.length}곳 · 피드 $feedCount개');
  for (final o in kOutlets) {
    stdout.writeln(
      '         ${o.code}  ${o.label.padRight(8)} 피드 ${o.feeds.length}개',
    );
  }

  stdout.writeln('[수집기] 첫 수집 시작…');
  await collector.runOnce();
  _report(collector, store);

  if (opts['once'] as bool) {
    collector.close();
    return;
  }

  // 주기 수집. 구글 트렌드는 분 단위로 갱신되므로 2분이면 충분하고,
  // 소스에 부담을 주지 않는 선이기도 하다. (plan.md §6.2 — 최소 60초 간격)
  Timer.periodic(interval, (_) async {
    await collector.runOnce();
    _report(collector, store);
  });

  final server = CollectorServer(store: store, collector: collector);
  final httpServer = await shelf_io.serve(server.handler, '0.0.0.0', port);

  stdout.writeln('[수집기] http://localhost:${httpServer.port} 에서 서빙 중');
  stdout.writeln(
    '         수집 주기 ${interval.inSeconds}초 · 상태 파일 ${opts['state']}',
  );
  stdout.writeln('         종료하려면 Ctrl+C');

  await ProcessSignal.sigint.watch().first;
  stdout.writeln('\n[수집기] 종료합니다…');
  await store.save();
  collector.close();
  await httpServer.close(force: true);
}

void _report(Collector collector, Store store) {
  final at = collector.lastRunAt;
  final stamp = at == null
      ? '-'
      : '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}:'
          '${at.second.toString().padLeft(2, '0')}';

  if (collector.lastError != null) {
    stdout.writeln('[$stamp] 실패 — ${collector.lastError}');
    return;
  }

  final live = store.issues.values.where((i) => i.status != 'archived').length;
  final archived = store.issues.length - live;
  final status = collector.sourceStatus.entries
      .map((e) => '${e.key}=${e.value}')
      .join('  ');

  stdout.writeln('[$stamp] 활성 $live · 아카이브 $archived   $status');
}
