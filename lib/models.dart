import 'package:flutter/material.dart';

/// 事件分類
class Category {
  final String name;
  final Color color;
  final IconData icon;
  const Category(this.name, this.color, this.icon);
}

const List<Category> categories = <Category>[
  Category('收入', Color(0xFFA86A10), Icons.payments_outlined),
  Category('購物', Color(0xFF2B6CB0), Icons.shopping_bag_outlined),
  Category('車輛', Color(0xFF4A5568), Icons.directions_car_outlined),
  Category('健康', Color(0xFFC2410C), Icons.favorite_border),
  Category('家庭人生', Color(0xFF6B46C1), Icons.home_outlined),
  Category('人情', Color(0xFFB83280), Icons.card_giftcard_outlined),
  Category('旅遊', Color(0xFF2F855A), Icons.flight_takeoff_outlined),
  Category('時事', Color(0xFF8A8376), Icons.public),
];

Category categoryOf(String name) {
  for (final c in categories) {
    if (c.name == name) return c;
  }
  return categories[4];
}

String two(int v) => v.toString().padLeft(2, '0');

/// 千分位
String fmtInt(int v) {
  final neg = v < 0;
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return neg ? '-$buf' : buf.toString();
}

/// 萬元，一位小數
String fmtWan(num v) {
  final w = v / 10000;
  final r = (w * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}

const List<String> monthNames = <String>[
  '一月', '二月', '三月', '四月', '五月', '六月',
  '七月', '八月', '九月', '十月', '十一月', '十二月',
];

/// 可以只有年、年＋月、或完整日期的日期
class FuzzyDate implements Comparable<FuzzyDate> {
  final int y;
  final int? m;
  final int? d;
  const FuzzyDate(this.y, [this.m, this.d]);

  /// 1 = 只有年，2 = 年月，3 = 完整日期
  int get precision => d != null ? 3 : (m != null ? 2 : 1);

  factory FuzzyDate.fromJson(Map<String, dynamic> j) =>
      FuzzyDate(j['y'] as int, j['m'] as int?, j['d'] as int?);

  Map<String, dynamic> toJson() => <String, dynamic>{'y': y, 'm': m, 'd': d};

  /// 年度大項排在該年最前面，月份大項排在該月最前面
  int get sortKey => y * 10000 + (m ?? 0) * 100 + (d ?? 0);

  @override
  int compareTo(FuzzyDate other) => sortKey.compareTo(other.sortKey);

  /// 換成實際日期：只有年→7/1，只有年月→15 日
  DateTime asDate() => DateTime(y, m ?? 7, d ?? (m == null ? 1 : 15));

  String format() {
    if (m == null) return '$y';
    if (d == null) return '$y/${two(m!)}';
    return '$y/${two(m!)}/${two(d!)}';
  }

  /// 時間軸左側的短標籤
  String shortLabel() {
    if (m == null) return '全年';
    if (d == null) return '${m!}月';
    return '${two(m!)}/${two(d!)}';
  }

  String describe() {
    if (m == null) return '$y 年（年度大項）';
    if (d == null) return '$y 年 ${m!} 月（月份大項）';
    return '$y 年 ${m!} 月 ${d!} 日';
  }
}

class ParsedDate {
  final FuzzyDate start;
  final FuzzyDate? end;
  const ParsedDate(this.start, this.end);

  String describe() {
    if (end == null) return start.describe();
    return '${start.format()} ～ ${end!.format()}（期間）';
  }

  String toInput() => end == null ? start.format() : '${start.format()}~${end!.format()}';
}

int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

bool _valid(int y, int? m, int? d) {
  if (y < 1900 || y > 2200) return false;
  if (m != null && (m < 1 || m > 12)) return false;
  if (d != null && (m == null || d < 1 || d > _daysInMonth(y, m))) return false;
  return true;
}

FuzzyDate? _parseFull(String s) {
  // 20080219 / 200802
  var mt = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s);
  if (mt != null) {
    final y = int.parse(mt.group(1)!), m = int.parse(mt.group(2)!), d = int.parse(mt.group(3)!);
    return _valid(y, m, d) ? FuzzyDate(y, m, d) : null;
  }
  // 2022/0818 這種漏打斜線
  mt = RegExp(r'^(\d{4})/(\d{2})(\d{2})$').firstMatch(s);
  if (mt != null) {
    final y = int.parse(mt.group(1)!), m = int.parse(mt.group(2)!), d = int.parse(mt.group(3)!);
    return _valid(y, m, d) ? FuzzyDate(y, m, d) : null;
  }
  mt = RegExp(r'^(\d{3,4})(?:/(\d{1,2}))?(?:/(\d{1,2}))?$').firstMatch(s);
  if (mt == null) return null;
  var y = int.parse(mt.group(1)!);
  if (y < 1000) y += 1911; // 民國年
  final int? m = mt.group(2) == null ? null : int.parse(mt.group(2)!);
  final int? d = mt.group(3) == null ? null : int.parse(mt.group(3)!);
  return _valid(y, m, d) ? FuzzyDate(y, m, d) : null;
}

/// 自動辨識日期：
/// 2008 → 年度大項；2008/2 → 月份大項；2008/2/19 → 當天
/// 也接受 2008年2月19日、2008-02-19、20080219、民國 111/8/23
/// 期間：2001/6/22~2003/4/24、2026/6/8~13、2026/5~8
ParsedDate? parseSmartDate(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  s = s
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[～〜至到]'), '~')
      .replaceAll(RegExp(r'[年月\.\-／]'), '/')
      .replaceAll('日', '')
      .replaceAll(RegExp(r'/+'), '/');
  final parts = s.split('~');
  if (parts.length > 2) return null;
  final start = _parseFull(parts[0].replaceAll(RegExp(r'/$'), ''));
  if (start == null) return null;
  if (parts.length == 1 || parts[1].isEmpty) return ParsedDate(start, null);

  final e = parts[1].replaceAll(RegExp(r'/$'), '');
  FuzzyDate? end;
  if (RegExp(r'^\d{4}').hasMatch(e)) {
    end = _parseFull(e);
  } else {
    final toks = e.split('/').where((t) => t.isNotEmpty).map(int.tryParse).toList();
    if (toks.any((t) => t == null)) return null;
    if (start.precision == 3) {
      if (toks.length == 1) end = FuzzyDate(start.y, start.m, toks[0]);
      if (toks.length == 2) end = FuzzyDate(start.y, toks[0], toks[1]);
    } else if (start.precision == 2 && toks.length == 1) {
      end = FuzzyDate(start.y, toks[0]);
    }
    if (end != null && !_valid(end.y, end.m, end.d)) end = null;
  }
  if (end == null || end.compareTo(start) < 0) return null;
  return ParsedDate(start, end);
}

class LifeEvent {
  String id;
  FuzzyDate start;
  FuzzyDate? end;
  String title;
  String note;
  String category;
  int? amount;
  List<String> photos;

  /// 標記（星號）：總覽右側會顯示被標記的事件
  bool starred;

  /// 人物標籤
  List<String> people;

  /// 每年紀念（總覽「即將到來」）
  bool anniversary;

  /// 物品使用狀況：還在用，或用到哪一天
  bool inUse;
  FuzzyDate? usedUntil;

  LifeEvent({
    required this.id,
    required this.start,
    this.end,
    required this.title,
    this.note = '',
    required this.category,
    this.amount,
    List<String>? photos,
    this.starred = false,
    List<String>? people,
    this.anniversary = false,
    this.inUse = false,
    this.usedUntil,
  })  : photos = photos ?? <String>[],
        people = people ?? <String>[];

  factory LifeEvent.fromJson(Map<String, dynamic> j) => LifeEvent(
        id: j['id'] as String,
        start: FuzzyDate.fromJson(j['start'] as Map<String, dynamic>),
        end: j['end'] == null ? null : FuzzyDate.fromJson(j['end'] as Map<String, dynamic>),
        title: (j['title'] ?? '') as String,
        note: (j['note'] ?? '') as String,
        category: (j['category'] ?? '家庭人生') as String,
        amount: j['amount'] as int?,
        photos: ((j['photos'] ?? <dynamic>[]) as List<dynamic>).cast<String>(),
        starred: (j['starred'] ?? false) as bool,
        people: ((j['people'] ?? <dynamic>[]) as List<dynamic>).cast<String>(),
        anniversary: (j['anniversary'] ?? false) as bool,
        inUse: (j['inUse'] ?? false) as bool,
        usedUntil: j['usedUntil'] == null ? null : FuzzyDate.fromJson(j['usedUntil'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'start': start.toJson(),
        'end': end?.toJson(),
        'title': title,
        'note': note,
        'category': category,
        'amount': amount,
        'photos': photos,
        'starred': starred,
        'people': people,
        'anniversary': anniversary,
        'inUse': inUse,
        'usedUntil': usedUntil?.toJson(),
      };

  bool get tracksUsage => inUse || usedUntil != null;

  /// 用了多久（月數）。日期不完整時以年中／月初估算，approx = true
  ({int months, bool approx})? usageSpan() {
    if (!tracksUsage) return null;
    final s = start.asDate();
    final e = usedUntil?.asDate() ?? DateTime.now();
    var months = (e.year - s.year) * 12 + (e.month - s.month);
    if (e.day < s.day) months--;
    if (months < 0) months = 0;
    final approx = start.precision < 3 || (usedUntil != null && usedUntil!.precision < 3);
    return (months: months, approx: approx);
  }

  String? usageText() {
    final u = usageSpan();
    if (u == null) return null;
    final y = u.months ~/ 12, m = u.months % 12;
    final span = u.months < 1 ? '不到 1 個月' : (y == 0 ? '$m 個月' : (m == 0 ? '$y 年' : '$y 年 $m 個月'));
    return '${inUse ? '已用' : '用了'} ${u.approx ? '約 ' : ''}$span';
  }

  String dateText() => end == null ? start.format() : '${start.format()} ～ ${end!.format()}';

  /// 從文字裡找里程（km / 公里）
  int? get mileage {
    final mt = RegExp(r'(\d[\d,]{3,})\s*(?:km|KM|Km|公里)').firstMatch('$title $note');
    if (mt == null) return null;
    return int.tryParse(mt.group(1)!.replaceAll(',', ''));
  }
}
