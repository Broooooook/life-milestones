import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'photos.dart';
import 'store.dart';

class ExportError implements Exception {
  final String message;
  const ExportError(this.message);
  @override
  String toString() => message;
}

class ExportResult {
  final String docUrl;
  final String sheetUrl;
  final int count;
  const ExportResult(this.docUrl, this.sheetUrl, this.count);
}

/// 送到 Apps Script 網頁應用程式。Apps Script 的 POST 會回 302，
/// 真正的結果要再用 GET 去 Location 拿。
Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> payload) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.isScheme('https') || !uri.host.contains('script.google')) {
    throw const ExportError('網址看起來不對，應該是 https://script.google.com/macros/s/…/exec');
  }
  final client = http.Client();
  try {
    final req = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'text/plain; charset=utf-8'
      ..body = jsonEncode(payload);
    var res = await http.Response.fromStream(await client.send(req)).timeout(const Duration(minutes: 4));
    var hops = 0;
    while (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
      final loc = res.headers['location'];
      if (loc == null || hops++ > 5) break;
      res = await client.get(Uri.parse(loc)).timeout(const Duration(minutes: 2));
    }
    if (res.statusCode != 200) {
      throw ExportError('伺服器回應 ${res.statusCode}，請確認部署時「誰可以存取」選的是「所有人」');
    }
    final dynamic j = _decode(res.bodyBytes);
    if (j is! Map<String, dynamic>) throw const ExportError('回應格式不對');
    if (j['ok'] != true) throw ExportError('${j['error'] ?? '匯出失敗'}');
    return j;
  } on TimeoutException {
    throw const ExportError('連線逾時，請稍後再試');
  } on ExportError {
    rethrow;
  } catch (e) {
    throw ExportError('連線失敗：$e');
  } finally {
    client.close();
  }
}

dynamic _decode(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const ExportError('收到的不是匯出服務的回應。請確認：部署成「網頁應用程式」、存取權選「所有人」，網址結尾是 /exec');
  }
}

/// 測試連線並完成配對
Future<void> testConnection() async {
  await _post(settings.exportUrl, <String, dynamic>{'key': settings.pairKey, 'ping': true});
}

/// 整份匯出（單向覆蓋）。照片先上傳 Google 還沒有的。
Future<ExportResult> exportNow({void Function(String step)? onProgress}) async {
  final names = <String>[for (final e in store.events) ...e.photos];
  if (names.isNotEmpty) {
    onProgress?.call('檢查照片…');
    final m = await _post(settings.exportUrl, <String, dynamic>{
      'key': settings.pairKey,
      'action': 'missingPhotos',
      'names': names,
    });
    final missing = ((m['missing'] ?? <dynamic>[]) as List<dynamic>).cast<String>();
    for (var i = 0; i < missing.length; i++) {
      onProgress?.call('上傳照片 ${i + 1} / ${missing.length}…');
      final f = photos.file(missing[i]);
      if (!await f.exists()) continue;
      await _post(settings.exportUrl, <String, dynamic>{
        'key': settings.pairKey,
        'action': 'uploadPhoto',
        'name': missing[i],
        'data': base64Encode(await f.readAsBytes()),
      });
    }
  }
  onProgress?.call('產生文件與試算表…');
  final j = await _post(settings.exportUrl, <String, dynamic>{
    'key': settings.pairKey,
    'exportedAt': DateTime.now().toIso8601String(),
    'events': store.events.map((e) => e.toJson()).toList(),
  });
  final r = ExportResult('${j['docUrl'] ?? ''}', '${j['sheetUrl'] ?? ''}', (j['count'] as num?)?.toInt() ?? 0);
  settings.recordExport(r.docUrl, r.sheetUrl);
  return r;
}

/// 開 APP 時：有設定好、開啟自動備份、且超過 7 天沒匯出 → 背景匯出一次
Future<void> maybeAutoExport() async {
  if (!settings.autoExport || settings.exportUrl.isEmpty || store.events.isEmpty) return;
  final last = DateTime.tryParse(settings.lastExport);
  if (last != null && DateTime.now().difference(last).inDays < 7) return;
  try {
    await exportNow();
  } catch (_) {
    // 靜默失敗，下次開 APP 再試
  }
}


class BackupInfo {
  final List<LifeEvent> events;
  final String exportedAt;
  const BackupInfo(this.events, this.exportedAt);
  int get photoCount => events.fold<int>(0, (a, e) => a + e.photos.length);
}

/// 讀 Google 上最近一次匯出的完整備份（還不寫入手機）
Future<BackupInfo> fetchBackup() async {
  final j = await _post(settings.exportUrl, <String, dynamic>{'key': settings.pairKey, 'action': 'restore'});
  final b = j['backup'];
  if (b is! Map<String, dynamic>) {
    throw const ExportError('Google 上還沒有備份，請先在原本的手機匯出一次');
  }
  final list = ((b['events'] ?? <dynamic>[]) as List<dynamic>)
      .map((e) => LifeEvent.fromJson(e as Map<String, dynamic>))
      .toList();
  return BackupInfo(list, '${b['exportedAt'] ?? ''}');
}

/// 用備份取代手機資料，並把手機上沒有的照片下載回來
Future<int> applyBackup(BackupInfo b, {void Function(String step)? onProgress}) async {
  await store.replaceAll(b.events);
  final names = <String>[for (final e in b.events) ...e.photos];
  var got = 0;
  for (var i = 0; i < names.length; i++) {
    final f = photos.file(names[i]);
    if (await f.exists()) continue;
    onProgress?.call('下載照片 ${i + 1} / ${names.length}…');
    try {
      final j = await _post(settings.exportUrl,
          <String, dynamic>{'key': settings.pairKey, 'action': 'getPhoto', 'name': names[i]});
      final data = j['data'];
      if (data is String && data.isNotEmpty) {
        await f.writeAsBytes(base64Decode(data), flush: true);
        got++;
      }
    } catch (_) {
      // 單張失敗就跳過
    }
  }
  return got;
}
