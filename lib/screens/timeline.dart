import 'package:flutter/material.dart';

import '../cpi.dart';
import '../models.dart';
import '../photos.dart';
import '../store.dart';
import '../widgets.dart';
import 'edit_event.dart';
import 'search_page.dart';
import 'year_review.dart';

/// 單年時間軸：左右滑動換年份；右上角可一次展開／收起全部細項
class TimelinePage extends StatefulWidget {
  final int year;
  final bool expandAll;
  final String? focusId;
  final void Function(int year) onYearChanged;
  final void Function(int year, String? focusId) onOpenYear;
  final VoidCallback onToggleExpandAll;

  const TimelinePage({
    super.key,
    required this.year,
    required this.expandAll,
    required this.focusId,
    required this.onYearChanged,
    required this.onOpenYear,
    required this.onToggleExpandAll,
  });

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  late PageController _pc;
  late int _year = widget.year;
  final Set<String> _open = <String>{};
  final Set<String> _hidden = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.focusId != null) _open.add(widget.focusId!);
    final i = store.years.indexOf(_year);
    _pc = PageController(initialPage: i < 0 ? 0 : i);
  }

  @override
  void didUpdateWidget(TimelinePage old) {
    super.didUpdateWidget(old);
    if (widget.focusId != null && widget.focusId != old.focusId) _open.add(widget.focusId!);
    if (widget.year != old.year && widget.year != _year) {
      _year = widget.year;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final i = store.years.indexOf(_year);
        if (i >= 0 && _pc.hasClients) _pc.jumpToPage(i);
      });
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _edit(LifeEvent e) async {
    final saved = await Navigator.of(context).push<LifeEvent>(
      MaterialPageRoute<LifeEvent>(builder: (_) => EditEventPage(existing: e)),
    );
    if (saved != null && saved.start.y != _year) widget.onOpenYear(saved.start.y, saved.id);
  }

  Future<void> _search() async {
    final e = await Navigator.of(context).push<LifeEvent>(
      MaterialPageRoute<LifeEvent>(builder: (_) => const SearchPage()),
    );
    if (e != null) {
      setState(() => _open.add(e.id));
      final i = store.years.indexOf(e.start.y);
      if (i >= 0 && _pc.hasClients) _pc.jumpToPage(i);
    }
  }

  void _filter() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('排列順序', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Text('舊的在上面')),
                  ButtonSegment<bool>(value: true, label: Text('新的在上面')),
                ],
                selected: <bool>{settings.timelineNewestFirst},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  settings.setTimelineNewestFirst(s.first);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 20),
              const Text('顯示哪些分類', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final c in categories)
                    FilterChip(
                      avatar: Dot(c.color),
                      label: Text(c.name),
                      selected: !_hidden.contains(c.name),
                      onSelected: (v) {
                        setSheet(() {});
                        setState(() => v ? _hidden.remove(c.name) : _hidden.add(c.name));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setSheet(() {});
                  setState(() => _hidden.clear());
                },
                child: const Text('全部顯示'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[store, settings]),
      builder: (context, _) {
        final years = store.years;
        if (years.isEmpty) {
          return const Center(child: Text('還沒有任何事件，按右下角＋新增第一筆'));
        }
        return PageView.builder(
            controller: _pc,
            itemCount: years.length,
            onPageChanged: (i) {
              _year = years[i];
              widget.onYearChanged(years[i]);
            },
            itemBuilder: (context, i) => _YearView(
              year: years[i],
              hasPrev: i > 0,
              hasNext: i < years.length - 1,
              onPrev: () => _pc.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut),
              onNext: () => _pc.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut),
              expandAll: widget.expandAll,
              open: _open,
              hidden: _hidden,
              onToggle: (id) => setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id)),
              onEdit: _edit,
              onSearch: _search,
              onFilter: _filter,
              onToggleExpandAll: widget.onToggleExpandAll,
            ),
        );
      },
    );
  }
}

class _YearView extends StatelessWidget {
  final int year;
  final bool hasPrev, hasNext, expandAll;
  final VoidCallback onPrev, onNext, onSearch, onFilter, onToggleExpandAll;
  final Set<String> open, hidden;
  final void Function(String id) onToggle;
  final void Function(LifeEvent e) onEdit;

  const _YearView({
    required this.year,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
    required this.expandAll,
    required this.open,
    required this.hidden,
    required this.onToggle,
    required this.onEdit,
    required this.onSearch,
    required this.onFilter,
    required this.onToggleExpandAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = store.ofYear(year);
    final list = all.where((e) => !hidden.contains(e.category)).toList();

    int? income;
    var bonus = 0;
    for (final e in all) {
      if (e.amount == null) continue;
      if (e.start.precision == 1 && RegExp(r'^年(度)?(所得|收入)').hasMatch(e.title)) income = e.amount;
      if (e.title.contains('紅利')) bonus += e.amount!;
    }

    final rows = <Widget>[];
    final yearLevel = list.where((e) => e.start.precision == 1).toList();
    if (yearLevel.isNotEmpty) {
      rows.add(_groupLabel(context, '全年大項'));
      for (final e in yearLevel) {
        rows.add(_tile(context, e));
      }
    }
    // 依設定：由舊到新，或由新到舊（月份大項永遠排在該月最前面）
    final desc = settings.timelineNewestFirst;
    final months = desc ? <int>[for (var m = 12; m >= 1; m--) m] : <int>[for (var m = 1; m <= 12; m++) m];
    for (final m in months) {
      final monthLevel = list.where((e) => e.start.m == m && e.start.d == null).toList();
      var days = list.where((e) => e.start.m == m && e.start.d != null).toList();
      if (desc) days = days.reversed.toList();
      if (monthLevel.isEmpty && days.isEmpty) continue;
      rows.add(_groupLabel(context, monthNames[m - 1]));
      for (final e in <LifeEvent>[...monthLevel, ...days]) {
        rows.add(_tile(context, e));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('生涯里程', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, letterSpacing: 1)),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      _arrow(context, Icons.chevron_left, hasPrev ? onPrev : null, '上一年'),
                      Text('$year', style: yearStyle(context, 34)),
                      _arrow(context, Icons.chevron_right, hasNext ? onNext : null, '下一年'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton.outlined(
              onPressed: onToggleExpandAll,
              tooltip: expandAll ? '收起全部細項' : '展開全部細項',
              isSelected: expandAll,
              icon: const Icon(Icons.unfold_more),
              selectedIcon: const Icon(Icons.unfold_less),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              onPressed: onFilter,
              tooltip: '排序與篩選',
              icon: Badge(isLabelVisible: hidden.isNotEmpty, smallSize: 8, child: const Icon(Icons.tune)),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(onPressed: onSearch, tooltip: '搜尋', icon: const Icon(Icons.search)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (settings.ageIn(year) != null) InfoChip('${settings.ageIn(year)} 歲'),
            if (income != null) InfoChip('所得 ${fmtWan(income)} 萬'),
            if (bonus > 0) InfoChip('紅利 ${fmtWan(bonus)} 萬'),
            InfoChip('${all.length} 筆'),
            ActionChip(
              avatar: Icon(Icons.auto_awesome, size: 16, color: cs.primary),
              label: const Text('年度回顧'),
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => YearReviewPage(year: year)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('左右滑動換年份・點 ☆ 標記的事件會顯示在總覽右側',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(child: Text('這一年沒有符合篩選的事件', style: TextStyle(color: cs.onSurfaceVariant))),
          ),
        ...rows,
      ],
    );
  }

  Widget _arrow(BuildContext context, IconData icon, VoidCallback? onTap, String tip) => IconButton(
        onPressed: onTap,
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon),
      );

  Widget _groupLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 64, top: 14, bottom: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _tile(BuildContext context, LifeEvent e) {
    final cs = Theme.of(context).colorScheme;
    final cat = categoryOf(e.category);
    final isOpen = expandAll || open.contains(e.id);
    final hasNote = e.note.trim().isNotEmpty;
    final meta = <String>[
      if (e.amount != null) '${fmtInt(e.amount!)} 元',
      if (e.end != null) '～${e.end!.format()}',
      if (e.mileage != null) '${fmtInt(e.mileage!)} km',
      if (e.usageText() != null) e.usageText()!,
      if (e.people.isNotEmpty) e.people.join('、'),
    ];
    final today = e.amount == null ? null : toTodayMoney(e.amount!, e.start.y);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Text(e.start.shortLabel(),
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 12,
            child: Column(
              children: <Widget>[
                Container(width: 2, height: 16, color: cs.outlineVariant),
                Dot(cat.color, size: 12),
                Expanded(child: Container(width: 2, color: cs.outlineVariant)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Card(
                elevation: isOpen ? 2 : 0,
                shadowColor: Colors.black26,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onToggle(e.id),
                  onLongPress: () => onEdit(e),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Text(e.title,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.35)),
                            ),
                            if (hasNote && !isOpen)
                              Padding(
                                padding: const EdgeInsets.only(left: 6, top: 2),
                                child: Icon(Icons.notes, size: 16, color: cs.onSurfaceVariant),
                              ),
                            if (e.photos.isNotEmpty && !isOpen)
                              Padding(
                                padding: const EdgeInsets.only(left: 6, top: 2),
                                child: Icon(Icons.photo_outlined, size: 16, color: cs.onSurfaceVariant),
                              ),
                            SizedBox(
                              width: 36,
                              height: 28,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                tooltip: e.starred ? '取消標記' : '標記到總覽',
                                onPressed: () => store.toggleStar(e.id),
                                icon: Icon(
                                  e.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                                  size: 22,
                                  color: e.starred ? const Color(0xFFD69E2E) : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: <Widget>[
                            Text(cat.name,
                                style: TextStyle(fontSize: 12, color: cat.color, fontWeight: FontWeight.w500)),
                            for (final m in meta)
                              Text(m, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          ],
                        ),
                        if (isOpen && today != null) ...<Widget>[
                          const SizedBox(height: 6),
                          Text('≈ 今天的 ${fmtInt(today)} 元（依$cpiNowLabel物價）',
                              style: TextStyle(fontSize: 12, color: cs.primary)),
                        ],
                        if (isOpen && hasNote) ...<Widget>[
                          const SizedBox(height: 8),
                          Divider(height: 1, color: cs.outlineVariant),
                          const SizedBox(height: 8),
                          Text(e.note, style: const TextStyle(fontSize: 14, height: 1.6)),
                        ],
                        if (isOpen && e.photos.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 10),
                          PhotoStrip(e.photos),
                        ],
                        if (isOpen)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => onEdit(e),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('編輯'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
