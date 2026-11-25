import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// 年份總覽：每一年一列，每個圓點是一筆事件（有細項的圓點會加外框）
/// 右側顯示那一年被標記（★）的事件
class OverviewPage extends StatelessWidget {
  final void Function(int year) onOpenYear;
  final void Function(int year, String id)? onOpenEvent;
  const OverviewPage({super.key, required this.onOpenYear, this.onOpenEvent});

  /// 那年今天：過去同月同日；沒有的話，前後 3 天內
  List<LifeEvent> _onThisDay() {
    final now = DateTime.now();
    final past = store.events.where((e) => e.start.y < now.year && e.start.precision == 3).toList();
    var hits = past.where((e) => e.start.m == now.month && e.start.d == now.day).toList();
    if (hits.isEmpty) {
      hits = past.where((e) {
        final d = DateTime(now.year, e.start.m!, e.start.d!).difference(DateTime(now.year, now.month, now.day)).inDays;
        return d.abs() <= 3;
      }).toList();
    }
    hits.sort((a, b) => b.start.compareTo(a.start));
    return hits;
  }

  /// 即將到來的紀念日（60 天內）
  List<({LifeEvent e, int days, int nth})> _upcoming() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <({LifeEvent e, int days, int nth})>[];
    for (final e in store.events.where((x) => x.anniversary && x.start.m != null)) {
      var next = DateTime(today.year, e.start.m!, e.start.d ?? 1);
      if (next.isBefore(today)) next = DateTime(today.year + 1, e.start.m!, e.start.d ?? 1);
      final days = next.difference(today).inDays;
      final nth = next.year - e.start.y;
      if (days <= 60 && nth > 0) out.add((e: e, days: days, nth: nth));
    }
    out.sort((a, b) => a.days.compareTo(b.days));
    return out;
  }

  Widget _sampleBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withAlpha(60)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.lightbulb_outline, color: cs.primary, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('現在看到的是虛構的範例資料，熟悉之後可以一鍵清除，開始記錄你自己的人生。',
                  style: TextStyle(fontSize: 13, height: 1.5)),
            ),
            TextButton(onPressed: () => confirmClearSamples(context), child: const Text('清除範例')),
          ],
        ),
      ),
    );
  }

  Widget _todayCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hits = _onThisDay();
    final ups = _upcoming();
    if (hits.isEmpty && ups.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (ups.isNotEmpty) ...<Widget>[
                Text('即將到來', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
                for (final u in ups.take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.cake_outlined, color: categoryOf(u.e.category).color),
                    title: Text('${u.e.title} ${u.nth} 週年'),
                    subtitle: Text(u.days == 0 ? '就是今天！' : '還有 ${u.days} 天'),
                    onTap: () => onOpenEvent?.call(u.e.start.y, u.e.id),
                  ),
              ],
              if (hits.isNotEmpty) ...<Widget>[
                Text('那年今天・${now.month}/${now.day}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
                for (final e in hits.take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Dot(categoryOf(e.category).color, size: 10),
                    minLeadingWidth: 12,
                    title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${now.year - e.start.y} 年前・${e.start.format()}'),
                    onTap: () => onOpenEvent?.call(e.start.y, e.id),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, List<LifeEvent> list) {
    final cs = Theme.of(context).colorScheme;
    final starred = list.where((e) => e.starred).toList();
    if (starred.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final e in starred.take(3))
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              const Icon(Icons.star_rounded, size: 13, color: Color(0xFFD69E2E)),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  e.title,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurface),
                ),
              ),
            ],
          ),
        if (starred.length > 3)
          Text('＋${starred.length - 3}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[store, settings]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        var years = store.allYears;
        if (settings.newestFirst) years = years.reversed.toList();
        final total = store.events.length;
        return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('生涯里程・總覽',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              store.allYears.isEmpty ? '' : '${store.allYears.first} – ${store.allYears.last}',
                              style: yearStyle(context, 28),
                            ),
                          ),
                          Text('共 $total 筆', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                        ],
                      ),
                      if (store.hasSamples) _sampleBanner(context),
                      _todayCard(context),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final c in categories)
                            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                              Dot(c.color),
                              const SizedBox(width: 4),
                              Text(c.name, style: const TextStyle(fontSize: 11)),
                            ]),
                          Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                            Dot(cs.surface, ring: true),
                            const SizedBox(width: 4),
                            const Text('有細項', style: TextStyle(fontSize: 11)),
                          ]),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('點年份看那一年的時間軸・右側顯示你在時間軸點了 ★ 的事件',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                sliver: SliverList.builder(
                  itemCount: years.length,
                  itemBuilder: (context, i) {
                    final y = years[i];
                    final list = store.ofYear(y);
                    final empty = list.isEmpty;
                    return InkWell(
                      onTap: empty ? null : () => onOpenYear(y),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: cs.outlineVariant.withAlpha(150))),
                        ),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 52,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text('$y',
                                      style: yearStyle(context, 16).copyWith(
                                          color: empty ? cs.onSurfaceVariant.withAlpha(120) : null)),
                                  if (settings.ageIn(y) != null)
                                    Text('${settings.ageIn(y)} 歲',
                                        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: empty
                                  ? Text('—', style: TextStyle(color: cs.onSurfaceVariant.withAlpha(120)))
                                  : Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: <Widget>[
                                        for (final e in list)
                                          Dot(categoryOf(e.category).color, ring: e.note.isNotEmpty),
                                      ],
                                    ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(width: 132, child: _tag(context, list)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
        );
      },
    );
  }
}


/// 確認後清除所有範例事件
Future<void> confirmClearSamples(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清除範例資料？'),
      content: const Text('只會刪除範例事件，你自己新增的事件不受影響。'),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除')),
      ],
    ),
  );
  if (ok == true) await store.clearSamples();
}
