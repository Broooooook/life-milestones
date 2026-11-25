import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../photos.dart';
import '../store.dart';
import '../widgets.dart';

/// 新增／編輯事件。日期欄會自動辨識：只打年份＝年度大項，打到月份＝月份大項
class EditEventPage extends StatefulWidget {
  final LifeEvent? existing;
  const EditEventPage({super.key, this.existing});

  @override
  State<EditEventPage> createState() => _EditEventPageState();
}

class _EditEventPageState extends State<EditEventPage> {
  late final TextEditingController _date;
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _category;
  late List<String> _people;
  late bool _anniv;
  late int _usage; // 0 不追蹤、1 還在用、2 已汰換
  late final TextEditingController _until;
  final TextEditingController _personCtl = TextEditingController();
  ParsedDate? _parsed;
  bool _saving = false;
  bool _saved = false;
  late List<String> _photos;
  final List<String> _added = <String>[];
  final List<String> _removed = <String>[];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    _date = TextEditingController(
        text: e == null ? '${now.year}/${two(now.month)}/${two(now.day)}' : ParsedDate(e.start, e.end).toInput());
    _title = TextEditingController(text: e?.title ?? '');
    _amount = TextEditingController(text: e?.amount == null ? '' : fmtInt(e!.amount!));
    _note = TextEditingController(text: e?.note ?? '');
    _category = e?.category ?? '家庭人生';
    _people = List<String>.of(e?.people ?? <String>[]);
    _anniv = e?.anniversary ?? false;
    _usage = e == null ? 0 : (e.inUse ? 1 : (e.usedUntil != null ? 2 : 0));
    _until = TextEditingController(text: e?.usedUntil?.format() ?? '');
    _photos = List<String>.of(e?.photos ?? <String>[]);
    _parsed = parseSmartDate(_date.text);
  }

  @override
  void dispose() {
    // 沒儲存就離開：把這次新加的照片檔刪掉
    if (!_saved) photos.delete(_added);
    _date.dispose();
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    _until.dispose();
    _personCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final p = _parsed;
    final init = p == null ? DateTime.now() : DateTime(p.start.y, p.start.m ?? 1, p.start.d ?? 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    setState(() {
      _date.text = '${picked.year}/${two(picked.month)}/${two(picked.day)}';
      _parsed = parseSmartDate(_date.text);
    });
  }

  Future<void> _save() async {
    final p = _parsed;
    if (p == null) {
      _toast('日期看不懂，請用 2008、2008/2 或 2008/2/19 的格式');
      return;
    }
    if (_title.text.trim().isEmpty) {
      _toast('請輸入標題');
      return;
    }
    final amtText = _amount.text.replaceAll(RegExp(r'[,\s]'), '');
    int? amt;
    if (amtText.isNotEmpty) {
      amt = int.tryParse(amtText);
      if (amt == null) {
        _toast('金額只能是數字');
        return;
      }
    }
    final tracks = _category == '購物' || _category == '車輛';
    FuzzyDate? until;
    if (tracks && _usage == 2) {
      until = parseSmartDate(_until.text)?.start;
      if (until == null || until.compareTo(p.start) < 0) {
        _toast('「用到」的日期看不懂，或比購入日期還早');
        return;
      }
    }
    _addPerson();
    setState(() => _saving = true);
    final e = LifeEvent(
      id: widget.existing?.id ?? store.newId(),
      start: p.start,
      end: p.end,
      title: _title.text.trim(),
      note: _note.text.trim(),
      category: _category,
      amount: amt,
      photos: List<String>.of(_photos),
      starred: widget.existing?.starred ?? false,
      people: List<String>.of(_people),
      anniversary: _anniv,
      inUse: tracks && _usage == 1,
      usedUntil: until,
    );
    await store.upsert(e);
    _saved = true;
    await photos.delete(_removed);
    if (mounted) Navigator.of(context).pop(e);
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除這筆事件？'),
        content: Text('「${e.title}」刪除後無法復原。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok == true) {
      await store.remove(e.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _addPhotos() async {
    final src = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('從相簿選（可多張）'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (src == null) return;
    try {
      final names = <String>[];
      if (src == 'camera') {
        final n = await photos.takePhoto();
        if (n != null) names.add(n);
      } else {
        names.addAll(await photos.pickFromGallery());
      }
      if (names.isEmpty || !mounted) return;
      setState(() {
        _photos.addAll(names);
        _added.addAll(names);
      });
    } catch (e) {
      _toast('無法加入照片：$e');
    }
  }

  void _addPerson() {
    final t = _personCtl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      for (final x in t.split(RegExp(r'[、,，\s]+'))) {
        if (x.isNotEmpty && !_people.contains(x)) _people.add(x);
      }
      _personCtl.clear();
    });
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 18),
        child: Text(t,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _parsed;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新增事件' : '編輯事件'),
        actions: <Widget>[
          if (widget.existing != null)
            IconButton(onPressed: _delete, tooltip: '刪除', icon: const Icon(Icons.delete_outline)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _saving ? null : _save, child: const Text('儲存')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: <Widget>[
          _label('日期（自動辨識）'),
          TextField(
            controller: _date,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              hintText: '2008、2008/2、2008/2/19、2001/6/22~2003/4/24',
              suffixIcon: IconButton(onPressed: _pickDate, tooltip: '從月曆選', icon: const Icon(Icons.calendar_month_outlined)),
            ),
            onChanged: (v) => setState(() => _parsed = parseSmartDate(v)),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Icon(p == null ? Icons.error_outline : Icons.check_circle_outline,
                  size: 16, color: p == null ? cs.error : cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p == null ? '看不懂這個日期' : '→ ${p.describe()}',
                  style: TextStyle(fontSize: 13, color: p == null ? cs.error : cs.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('只打年份＝那年的年度大項；打到月份＝那個月的大項；期間用 ~ 連接',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          _label('標題'),
          TextField(
            controller: _title,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: '例如：更換四顆輪胎'),
          ),
          _label('分類'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final c in categories)
                ChoiceChip(
                  avatar: Dot(c.color),
                  label: Text(c.name),
                  selected: _category == c.name,
                  onSelected: (_) => setState(() => _category = c.name),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('每年紀念'),
            subtitle: const Text('像結婚、交屋：每年快到時會顯示在總覽的「即將到來」'),
            value: _anniv,
            onChanged: (v) => setState(() => _anniv = v),
          ),
          _label('金額（選填）'),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9,\-]'))],
            decoration: const InputDecoration(prefixText: 'NT\$ ', hintText: '0'),
          ),
          if (_category == '購物' || _category == '車輛') ...<Widget>[
            _label('使用狀況（物品用了多久）'),
            SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text('不追蹤')),
                ButtonSegment<int>(value: 1, label: Text('還在用')),
                ButtonSegment<int>(value: 2, label: Text('已汰換')),
              ],
              selected: <int>{_usage},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _usage = v.first),
            ),
            if (_usage == 2) ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                controller: _until,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: '用到', hintText: '2015/1/31、2015/1 或 2015'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
          _label('備註（可多行）'),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(hintText: '細項、心情、明細……'),
          ),
          _label('人物（選填）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final p in _people)
                InputChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(p),
                  onDeleted: () => setState(() => _people.remove(p)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _personCtl,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '輸入名字後按＋，例如：小安',
              suffixIcon: IconButton(onPressed: _addPerson, tooltip: '加入人物', icon: const Icon(Icons.add)),
            ),
            onSubmitted: (_) => _addPerson(),
          ),
          Builder(builder: (context) {
            final sug = store.allPeople.where((x) => !_people.contains(x)).take(8).toList();
            if (sug.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final x in sug)
                    ActionChip(
                      label: Text('＋$x'),
                      onPressed: () => setState(() => _people.add(x)),
                    ),
                ],
              ),
            );
          }),
          _label('照片'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (var i = 0; i < _photos.length; i++)
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    PhotoThumb(_photos[i], onTap: () => openPhotoViewer(context, _photos, i)),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Material(
                        color: cs.inverseSurface,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() {
                            final n = _photos.removeAt(i);
                            if (_added.remove(n)) {
                              photos.delete(<String>[n]);
                            } else {
                              _removed.add(n);
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.close, size: 16, color: cs.onInverseSurface, semanticLabel: '移除照片'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              InkWell(
                onTap: _addPhotos,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.add_a_photo_outlined, color: cs.onSurfaceVariant),
                      const SizedBox(height: 4),
                      Text('加入', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
