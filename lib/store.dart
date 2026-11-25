import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'photos.dart';

/// 所有事件，存在手機本機的 events.json
class EventStore extends ChangeNotifier {
  final List<LifeEvent> _events = <LifeEvent>[];
  bool loaded = false;
  String? loadError;

  List<LifeEvent> get events => List<LifeEvent>.unmodifiable(_events);

  Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  Future<void> load() async {
    try {
      await photos.init();
      final f = await _file('events.json');
      String text;
      if (await f.exists()) {
        text = await f.readAsString();
      } else {
        text = await rootBundle.loadString('assets/sample.json');
        await f.writeAsString(text, flush: true);
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      _events
        ..clear()
        ..addAll((j['events'] as List<dynamic>)
            .map((e) => LifeEvent.fromJson(e as Map<String, dynamic>)));
      _sort();
      if (((j['version'] ?? 1) as int) < 2) {
        _migrateV2();
        await _save();
      }
    } catch (e) {
      loadError = '$e';
    }
    loaded = true;
    notifyListeners();
  }

  void _sort() => _events.sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

  Future<void> _save() async {
    final f = await _file('events.json');
    if (await f.exists()) {
      await f.copy('${f.path}.bak');
    }
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent(' ').convert(<String, dynamic>{
        'version': 2,
        'events': _events.map((e) => e.toJson()).toList(),
      }),
      flush: true,
    );
    await tmp.rename(f.path);
  }

  Future<void> upsert(LifeEvent e) async {
    final i = _events.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      _events[i] = e;
    } else {
      _events.add(e);
    }
    _sort();
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    for (final e in _events.where((x) => x.id == id)) {
      await photos.delete(e.photos);
    }
    _events.removeWhere((x) => x.id == id);
    notifyListeners();
    await _save();
  }

  /// v2：舊資料升級——結婚紀念日、備註裡寫的「汰換於」日期（只做一次）
  void _migrateV2() {
    for (final e in _events) {
      final t = '${e.title} ${e.note}';
      if (e.title.contains('結婚') && e.category == '家庭人生' && e.start.precision == 3) {
        e.anniversary = true;
      }
      final m = RegExp(r'汰換於\s*(\d{4})/(\d{1,2})(?:/(\d{1,2}))?').firstMatch(t);
      if (m != null && e.usedUntil == null) {
        e.usedUntil = FuzzyDate(int.parse(m.group(1)!), int.parse(m.group(2)!),
            m.group(3) == null ? null : int.parse(m.group(3)!));
      }
    }
  }

  /// 從 Google 備份還原：整份取代
  Future<void> replaceAll(List<LifeEvent> list) async {
    _events
      ..clear()
      ..addAll(list);
    _sort();
    notifyListeners();
    await _save();
  }

  /// 範例事件（id 以 sample- 開頭）
  bool get hasSamples => _events.any((e) => e.id.startsWith('sample-'));

  Future<void> clearSamples() async {
    _events.removeWhere((e) => e.id.startsWith('sample-'));
    notifyListeners();
    await _save();
  }

  /// 所有人物，依出現次數排序
  List<String> get allPeople {
    final c = <String, int>{};
    for (final e in _events) {
      for (final p in e.people) {
        c[p] = (c[p] ?? 0) + 1;
      }
    }
    final l = c.keys.toList()..sort((a, b) => c[b]!.compareTo(c[a]!));
    return l;
  }

  Future<void> toggleStar(String id) async {
    final i = _events.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _events[i].starred = !_events[i].starred;
    notifyListeners();
    await _save();
  }

  String newId() => 'e${DateTime.now().microsecondsSinceEpoch}';

  /// 有事件的年份，由舊到新
  List<int> get years {
    final s = <int>{for (final e in _events) e.start.y};
    final l = s.toList()..sort();
    return l;
  }

  /// 從最早到最晚的每一年（包含沒有記錄的年份）
  List<int> get allYears {
    final ys = years;
    if (ys.isEmpty) return <int>[DateTime.now().year];
    final last = ys.last > DateTime.now().year ? ys.last : DateTime.now().year;
    return <int>[for (var y = ys.first; y <= last; y++) y];
  }

  List<LifeEvent> ofYear(int y) => _events.where((e) => e.start.y == y).toList();

  List<LifeEvent> search(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return <LifeEvent>[];
    return _events
        .where((e) =>
            e.title.toLowerCase().contains(t) ||
            e.note.toLowerCase().contains(t) ||
            e.category.contains(t) ||
            e.people.any((p) => p.toLowerCase().contains(t)) ||
            e.dateText().contains(t))
        .toList()
        .reversed
        .toList();
  }
}

final EventStore store = EventStore();

enum ThemeChoice { paper, dark, system }

const List<Color> accentColors = <Color>[
  Color(0xFF0F5E5C),
  Color(0xFF3B4BA8),
  Color(0xFFA2412A),
  Color(0xFF3A3632),
];
const List<String> accentNames = <String>['青綠', '靛藍', '赭紅', '墨黑'];

/// 設定（佈景主題、字型大小、排序……）
class AppSettings extends ChangeNotifier {
  ThemeChoice theme = ThemeChoice.paper;
  int accent = 0;
  double fontScale = 1.0;
  bool newestFirst = true;
  bool timelineNewestFirst = false;
  int startTab = 0;

  // 匯出到 Google
  String exportUrl = '';
  String pairKey = '';
  String lastExport = '';
  String docUrl = '';
  String sheetUrl = '';
  bool autoExport = true;

  /// 出生年月（年齡軸），例如 "1977/5"
  String birth = '';

  SharedPreferences? _p;

  Color get accentColor => accentColors[accent.clamp(0, accentColors.length - 1)];

  Future<void> load() async {
    try {
      await photos.init();
      _p = await SharedPreferences.getInstance();
      theme = ThemeChoice.values[(_p!.getInt('theme') ?? 0).clamp(0, 2)];
      accent = _p!.getInt('accent') ?? 0;
      fontScale = _p!.getDouble('fontScale') ?? 1.0;
      newestFirst = _p!.getBool('newestFirst') ?? true;
      timelineNewestFirst = _p!.getBool('timelineNewestFirst') ?? false;
      startTab = _p!.getInt('startTab') ?? 0;
      exportUrl = _p!.getString('exportUrl') ?? '';
      lastExport = _p!.getString('lastExport') ?? '';
      docUrl = _p!.getString('docUrl') ?? '';
      sheetUrl = _p!.getString('sheetUrl') ?? '';
      autoExport = _p!.getBool('autoExport') ?? true;
      birth = _p!.getString('birth') ?? '';
      pairKey = _p!.getString('pairKey') ?? '';
      if (pairKey.isEmpty) {
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
        final r = Random.secure();
        pairKey = List<String>.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
        await _p!.setString('pairKey', pairKey);
      }
    } catch (_) {}
  }

  void setTheme(ThemeChoice v) {
    theme = v;
    _p?.setInt('theme', v.index);
    notifyListeners();
  }

  void setAccent(int v) {
    accent = v;
    _p?.setInt('accent', v);
    notifyListeners();
  }

  void setFontScale(double v) {
    fontScale = v;
    _p?.setDouble('fontScale', v);
    notifyListeners();
  }

  void setTimelineNewestFirst(bool v) {
    timelineNewestFirst = v;
    _p?.setBool('timelineNewestFirst', v);
    notifyListeners();
  }

  void setNewestFirst(bool v) {
    newestFirst = v;
    _p?.setBool('newestFirst', v);
    notifyListeners();
  }

  FuzzyDate? get birthDate => parseSmartDate(birth)?.start;

  /// 那一年幾歲（以生日當年的歲數計）
  int? ageIn(int year) {
    final b = birthDate;
    if (b == null || year < b.y) return null;
    return year - b.y;
  }

  void setBirth(String v) {
    birth = v.trim();
    _p?.setString('birth', birth);
    notifyListeners();
  }

  void setPairKey(String v) {
    pairKey = v.trim();
    _p?.setString('pairKey', pairKey);
    notifyListeners();
  }

  void setExportUrl(String v) {
    exportUrl = v.trim();
    _p?.setString('exportUrl', exportUrl);
    notifyListeners();
  }

  void setAutoExport(bool v) {
    autoExport = v;
    _p?.setBool('autoExport', v);
    notifyListeners();
  }

  void recordExport(String doc, String sheet) {
    lastExport = DateTime.now().toIso8601String();
    docUrl = doc;
    sheetUrl = sheet;
    _p?.setString('lastExport', lastExport);
    _p?.setString('docUrl', doc);
    _p?.setString('sheetUrl', sheet);
    notifyListeners();
  }

  void setStartTab(int v) {
    startTab = v;
    _p?.setInt('startTab', v);
    notifyListeners();
  }
}

final AppSettings settings = AppSettings();
