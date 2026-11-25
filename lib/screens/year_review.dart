import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../lock.dart';
import '../models.dart';
import '../photos.dart';
import '../store.dart';

/// 年度回顧：一張可以存成圖片、分享的卡片
class YearReviewPage extends StatefulWidget {
  final int year;
  const YearReviewPage({super.key, required this.year});

  @override
  State<YearReviewPage> createState() => _YearReviewPageState();
}

class _YearReviewPageState extends State<YearReviewPage> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/生涯里程_${widget.year}_年度回顧.png');
      await f.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      appLock.suspendOnce();
      await Share.shareXFiles(<XFile>[XFile(f.path, mimeType: 'image/png')], text: '${widget.year} 年度回顧');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('無法產生圖片：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = store.years;
    final i = years.indexOf(widget.year);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.year} 年度回顧'),
        actions: <Widget>[
          IconButton(
            tooltip: '上一年',
            onPressed: i > 0
                ? () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => YearReviewPage(year: years[i - 1])))
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '下一年',
            onPressed: i >= 0 && i < years.length - 1
                ? () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => YearReviewPage(year: years[i + 1])))
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Center(
            child: RepaintBoundary(
              key: _cardKey,
              child: YearReviewCard(year: widget.year, accent: Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            label: const Text('存成圖片／分享'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          Text('分享選單裡可以選「儲存到相簿」或直接傳 LINE。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 卡片本體（固定淺色紙感，不受深色主題影響，存成圖片才好看）
class YearReviewCard extends StatelessWidget {
  final int year;
  final Color accent;
  const YearReviewCard({super.key, required this.year, required this.accent});

  static const Color _paper = Color(0xFFF6F3EC);
  static const Color _ink = Color(0xFF1D1B18);
  static const Color _muted = Color(0xFF6B655B);

  @override
  Widget build(BuildContext context) {
    final list = store.ofYear(year);
    final age = settings.ageIn(year);
    final photoNames = <String>[for (final e in list) ...e.photos];
    final starred = list.where((e) => e.starred).toList();
    final highlights = starred.isNotEmpty
        ? starred
        : list.where((e) => e.category == '家庭人生' || e.category == '旅遊').toList();

    final byCat = <String, int>{};
    for (final e in list) {
      byCat[e.category] = (byCat[e.category] ?? 0) + 1;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    int? income;
    var bonus = 0;
    LifeEvent? biggest;
    for (final e in list) {
      if (e.amount == null) continue;
      if (e.start.precision == 1 && RegExp(r'^年(度)?(所得|收入)').hasMatch(e.title)) income = e.amount;
      if (e.title.contains('紅利')) bonus += e.amount!;
      if ((e.category == '購物' || e.category == '車輛' || e.category == '旅遊') &&
          (biggest == null || e.amount! > biggest.amount!)) {
        biggest = e;
      }
    }
    final trips = list.where((e) => e.category == '旅遊').length;

    TextStyle t(double size, {FontWeight w = FontWeight.w400, Color c = _ink, String? family}) =>
        TextStyle(fontSize: size, fontWeight: w, color: c, fontFamily: family, height: 1.35);

    Widget stat(String n, String label) => Expanded(
          child: Column(
            children: <Widget>[
              Text(n, style: t(26, w: FontWeight.w700, family: 'serif')),
              Text(label, style: t(12, c: _muted)),
            ],
          ),
        );

    return MediaQuery(
      // 卡片固定字級，存成圖片時版面才穩定
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('生涯里程・年度回顧', style: t(12, c: _muted).copyWith(letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text('$year', style: t(56, w: FontWeight.w700, c: accent, family: 'serif').copyWith(height: 1)),
                if (age != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 6),
                    child: Text('$age 歲的這一年', style: t(15, c: _muted)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(children: <Widget>[
              stat('${list.length}', '件事'),
              stat('${photoNames.length}', '張照片'),
              stat('$trips', '次旅行'),
            ]),
            const SizedBox(height: 16),
            if (cats.isNotEmpty) ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: <Widget>[
                      for (final c in cats) Expanded(flex: c.value, child: Container(color: categoryOf(c.key).color)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: <Widget>[
                  for (final c in cats.take(4))
                    Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: categoryOf(c.key).color, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text('${c.key} ${c.value}', style: t(11, c: _muted)),
                    ]),
                ],
              ),
            ],
            if (highlights.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(starred.isNotEmpty ? '★ 這一年的大事' : '這一年的大事', style: t(13, w: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final e in highlights.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(width: 50, child: Text(e.start.shortLabel(), style: t(12, c: _muted))),
                      Expanded(
                          child: Text(e.title, style: t(14), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
            if (income != null || bonus > 0 || biggest != null) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (income != null) Text('所得 ${fmtWan(income)} 萬', style: t(13)),
                    if (bonus > 0) Text('紅利 ${fmtWan(bonus)} 萬', style: t(13)),
                    if (biggest != null)
                      Text('最大一筆：${biggest.title}（${fmtInt(biggest.amount!)} 元）',
                          style: t(13), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
            if (photoNames.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  for (var k = 0; k < photoNames.length && k < 3; k++)
                    Padding(
                      padding: EdgeInsets.only(right: k < 2 ? 8 : 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(photos.file(photoNames[k]),
                            width: 98, height: 98, fit: BoxFit.cover, cacheWidth: 300,
                            errorBuilder: (_, __, ___) => const SizedBox(width: 98, height: 98)),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Text('我的生涯里程', style: t(11, c: _muted)),
          ],
        ),
      ),
    );
  }
}
