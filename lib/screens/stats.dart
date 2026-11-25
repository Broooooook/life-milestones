import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'edit_event.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('生涯里程・統計', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text('統計', style: yearStyle(context, 28)),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: '收入'),
              Tab(text: '支出'),
              Tab(text: '物品'),
              Tab(text: '車輛'),
              Tab(text: '健康'),
              Tab(text: '人物'),
            ],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: store,
              // 不用 const，資料變動時才會重畫
              builder: (context, _) => TabBarView(
                // ignore: prefer_const_constructors, prefer_const_literals_to_create_immutables
                children: <Widget>[
                  _IncomeTab(),
                  _SpendTab(),
                  _ItemsTab(),
                  _CategoryListTab('車輛'),
                  _CategoryListTab('健康'),
                  _PeopleTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _openEdit(BuildContext context, LifeEvent e) {
  Navigator.of(context).push<LifeEvent>(MaterialPageRoute<LifeEvent>(builder: (_) => EditEventPage(existing: e)));
}

/// 年份長條圖；沒有資料的年份畫成虛框
class YearBars extends StatelessWidget {
  final Map<int, int> data;
  final double height;
  const YearBars({super.key, required this.data, this.height = 150});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (data.isEmpty) {
      return SizedBox(
          height: 60, child: Center(child: Text('還沒有資料', style: TextStyle(color: cs.onSurfaceVariant))));
    }
    final ys = data.keys.toList()..sort();
    final first = ys.first, last = ys.last;
    final maxV = data.values.fold<int>(1, (a, b) => b > a ? b : a);
    final mid = first + ((last - first) ~/ 2);
    return Column(
      children: <Widget>[
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var y = first; y <= last; y++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Tooltip(
                      message: data[y] == null ? '$y：沒有記錄' : '$y：${fmtInt(data[y]!)}',
                      triggerMode: TooltipTriggerMode.tap,
                      child: data[y] == null
                          ? Container(
                              height: height * 0.16,
                              decoration: BoxDecoration(
                                border: Border.all(color: cs.outlineVariant),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            )
                          : Container(
                              height: (height * data[y]! / maxV).clamp(3.0, height),
                              decoration: BoxDecoration(
                                color: y == last ? cs.primary : const Color(0xFFC9A465),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (final y in <int>{first, mid, last})
              Text('$y', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label, value, sub;
  const _Kpi(this.label, this.value, this.sub);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value, style: yearStyle(context, 22)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _IncomeTab extends StatelessWidget {
  const _IncomeTab();

  @override
  Widget build(BuildContext context) {
    final income = <int, int>{};
    final bonus = <int, int>{};
    final raises = <LifeEvent>[];
    for (final e in store.events) {
      if (e.amount == null) continue;
      if (e.start.precision == 1 && RegExp(r'^年(度)?(所得|收入)').hasMatch(e.title)) {
        income[e.start.y] = e.amount!;
      }
      if (e.title.contains('紅利')) bonus[e.start.y] = (bonus[e.start.y] ?? 0) + e.amount!;
      if (e.title.contains('調薪')) raises.add(e);
    }
    final raiseTotal = raises.fold<int>(0, (a, e) => a + e.amount!);
    final zeroYears = raises.where((e) => e.amount == 0).map((e) => e.start.y).toList();
    final topIncome = income.entries.isEmpty
        ? null
        : income.entries.reduce((a, b) => b.value > a.value ? b : a);
    final recentBonus = (bonus.keys.toList()..sort()).reversed.take(5).map((y) => bonus[y]!).toList();
    final avgBonus = recentBonus.isEmpty ? 0 : recentBonus.reduce((a, b) => a + b) / recentBonus.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: <Widget>[
        SectionCard(
          title: '年所得（萬元）',
          subtitle: topIncome == null ? null : '最高 ${topIncome.key} 年 ${fmtWan(topIncome.value)}',
          child: YearBars(data: income),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '年度紅利',
          subtitle: recentBonus.isEmpty ? null : '近 5 年平均 ${fmtWan(avgBonus)} 萬',
          child: YearBars(data: bonus, height: 80),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: _Kpi('調薪累計（${raises.length} 筆）', '+${fmtInt(raiseTotal)}', '元／月')),
            const SizedBox(width: 12),
            Expanded(
              child: _Kpi('調薪 0 元', '${zeroYears.length} 次', zeroYears.isEmpty ? '—' : zeroYears.join('・')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '調薪紀錄',
          child: Column(
            children: <Widget>[
              for (final e in raises.reversed)
                EventListTile(e, trailing: '+${fmtInt(e.amount!)}', onTap: () => _openEdit(context, e)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('提示：標題以「年所得／年度所得／年收入」開頭、日期只填年份的事件，會算進年所得圖。',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SpendTab extends StatelessWidget {
  const _SpendTab();

  @override
  Widget build(BuildContext context) {
    const spendCats = <String>{'購物', '車輛', '健康', '旅遊'};
    final perYear = <int, int>{};
    final items = <LifeEvent>[];
    for (final e in store.events) {
      if (e.amount == null || !spendCats.contains(e.category)) continue;
      if (e.title.startsWith('售出')) continue;
      perYear[e.start.y] = (perYear[e.start.y] ?? 0) + e.amount!;
      items.add(e);
    }
    // 細項一律依日期，最新的在最上面
    items.sort((a, b) => b.start.compareTo(a.start));
    final total = items.fold<int>(0, (a, e) => a + e.amount!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: <Widget>[
        SectionCard(
          title: '每年大筆支出',
          subtitle: '合計 ${fmtWan(total)} 萬',
          child: YearBars(data: perYear),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '支出明細（${items.length} 筆）',
          child: Column(
            children: <Widget>[
              for (final e in items)
                EventListTile(e, trailing: fmtInt(e.amount!), onTap: () => _openEdit(context, e)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('包含購物、車輛、健康、旅遊分類中有填金額的事件。',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _CategoryListTab extends StatelessWidget {
  final String category;
  const _CategoryListTab(this.category);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = store.events.where((e) => e.category == category).toList().reversed.toList();
    final total = list.fold<int>(0, (a, e) => a + (e.amount ?? 0));
    final withKm = list.where((e) => e.mileage != null).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _Kpi('$category事件', '${list.length} 筆', '全部年份')),
            const SizedBox(width: 12),
            Expanded(child: _Kpi('有記金額的合計', fmtInt(total), '元')),
          ],
        ),
        if (category == '車輛' && withKm.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(
            title: '里程紀錄',
            child: Column(
              children: <Widget>[
                for (final e in withKm)
                  EventListTile(e, trailing: '${fmtInt(e.mileage!)} km', onTap: () => _openEdit(context, e)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: '全部$category紀錄',
          child: list.isEmpty
              ? Text('還沒有資料', style: TextStyle(color: cs.onSurfaceVariant))
              : Column(
                  children: <Widget>[
                    for (final e in list)
                      EventListTile(e,
                          trailing: e.amount == null ? null : fmtInt(e.amount!), onTap: () => _openEdit(context, e)),
                  ],
                ),
        ),
      ],
    );
  }
}


/// 物品用了多久
class _ItemsTab extends StatelessWidget {
  const _ItemsTab();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = store.events.where((e) => e.tracksUsage).toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    final retired = items.where((e) => e.usedUntil != null).toList();
    final avgMonths = retired.isEmpty
        ? null
        : retired.fold<int>(0, (a, e) => a + e.usageSpan()!.months) / retired.length;
    String perYear(LifeEvent e) {
      final m = e.usageSpan()!.months;
      if (e.amount == null || m < 1) return '';
      return '每年約 ${fmtInt((e.amount! / (m / 12)).round())} 元';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _Kpi('還在用', '${items.where((e) => e.inUse).length} 件', '追蹤中的物品')),
            const SizedBox(width: 12),
            Expanded(
              child: _Kpi('已汰換的平均壽命', avgMonths == null ? '—' : '${(avgMonths / 12).toStringAsFixed(1)} 年',
                  '${retired.length} 件'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '物品清單',
          child: items.isEmpty
              ? Text('還沒有追蹤的物品。編輯購物或車輛事件，在「使用狀況」選「還在用」或「已汰換」。',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5))
              : Column(
                  children: <Widget>[
                    for (final e in items)
                      InkWell(
                        onTap: () => _openEdit(context, e),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Dot(e.inUse ? cs.primary : cs.outline),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(e.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${e.start.format()} → ${e.usedUntil?.format() ?? '現在'}'
                                      '${perYear(e).isEmpty ? '' : '・${perYear(e)}'}',
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(e.usageText()!.replaceFirst(RegExp(r'^(已用|用了) '), ''),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 人物：每個人出現在哪些事件
class _PeopleTab extends StatelessWidget {
  const _PeopleTab();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final people = store.allPeople;
    if (people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('還沒有人物標籤。編輯事件時在「人物」加上名字。',
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: <Widget>[
        for (final p in people)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Builder(builder: (context) {
                final list = store.events.where((e) => e.people.contains(p)).toList().reversed.toList();
                return ExpansionTile(
                  shape: const Border(),
                  leading: CircleAvatar(
                    backgroundColor: cs.primary.withAlpha(30),
                    child: Text(p.characters.first, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(p, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${list.length} 件事・${list.last.start.y} – ${list.first.start.y}'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  children: <Widget>[
                    for (final e in list) EventListTile(e, onTap: () => _openEdit(context, e)),
                  ],
                );
              }),
            ),
          ),
      ],
    );
  }
}
