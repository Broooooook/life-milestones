import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../export.dart';
import '../lock.dart';
import '../store.dart';
import '../widgets.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  late final TextEditingController _url = TextEditingController(text: settings.exportUrl);
  bool _busy = false;
  String? _status;
  bool _statusError = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    appLock.suspendOnce();
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法開啟連結')));
    }
  }

  Future<void> _copyScript() async {
    final code = await rootBundle.loadString('google/Code.gs');
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('程式碼已複製')));
    }
  }

  Future<void> _run(Future<String> Function() job) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final msg = await job();
      setState(() {
        _status = msg;
        _statusError = false;
      });
      _snack(msg);
    } catch (e) {
      setState(() {
        _status = '$e';
        _statusError = true;
      });
      _snack('失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
  }

  Future<String> _saveAndTest() async {
    settings.setExportUrl(_url.text);
    await testConnection();
    return '連線成功，已完成配對！可以按「立即匯出」了';
  }

  String? _progress;

  Future<String> _export() async {
    final r = await exportNow(onProgress: (step) {
      if (mounted) setState(() => _progress = step);
    });
    _progress = null;
    return '匯出完成：${r.count} 筆';
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _status = null;
      _progress = '讀取 Google 備份…';
    });
    BackupInfo? b;
    try {
      b = await fetchBackup();
    } catch (e) {
      setState(() {
        _busy = false;
        _progress = null;
        _status = '$e';
        _statusError = true;
      });
      _snack('失敗：$e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
    });
    final t = DateTime.tryParse(b!.exportedAt)?.toLocal();
    final when = t == null ? '' : '（${t.year}/${t.month}/${t.day} 匯出）';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用 Google 備份取代手機資料？'),
        content: Text('Google 備份$when有 ${b!.events.length} 筆事件、${b.photoCount} 張照片。\n\n'
            '手機上目前的 ${store.events.length} 筆會被取代，無法復原。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('還原')),
        ],
      ),
    );
    if (ok != true) return;
    final BackupInfo backup = b!;
    await _run(() async {
      final got = await applyBackup(backup, onProgress: (step) {
        if (mounted) setState(() => _progress = step);
      });
      _progress = null;
      return '還原完成：${backup.events.length} 筆事件，下載 $got 張照片';
    });
  }

  Future<void> _enterPairKey() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('輸入舊手機的配對碼'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: '32 個英數字')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('使用')),
        ],
      ),
    );
    if (code == null || code.trim().length < 16) return;
    settings.setPairKey(code);
    _snack('已改用這組配對碼');
  }

  String _lastText() {
    final t = DateTime.tryParse(settings.lastExport);
    if (t == null) return '尚未匯出';
    final l = t.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('匯出到 Google')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final ready = settings.exportUrl.isNotEmpty;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: <Widget>[
              Text('單向備份：APP → Google 文件＋Google 試算表。每次都是整份重寫，請在 APP 裡修改內容。',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
              const SizedBox(height: 16),
              SectionCard(
                title: '狀態',
                subtitle: '上次匯出：${_lastText()}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: ready && !_busy ? () => _run(_export) : null,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(_busy ? (_progress ?? '處理中，約 10–40 秒…') : '立即匯出'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                    if (_status != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(_status!, style: TextStyle(color: _statusError ? cs.error : cs.primary, height: 1.5)),
                    ],
                    if (settings.docUrl.isNotEmpty || settings.sheetUrl.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          if (settings.docUrl.isNotEmpty)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _open(settings.docUrl),
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('開啟文件'),
                              ),
                            ),
                          const SizedBox(width: 10),
                          if (settings.sheetUrl.isNotEmpty)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _open(settings.sheetUrl),
                                icon: const Icon(Icons.table_chart_outlined),
                                label: const Text('開啟試算表'),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自動備份'),
                      subtitle: const Text('開啟 APP 時，如果超過 7 天沒匯出就自動匯出一次'),
                      value: settings.autoExport,
                      onChanged: settings.setAutoExport,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: '從 Google 還原',
                subtitle: '換手機、重裝時用',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('用 Google 上最近一次匯出的備份，取代這支手機上的資料，照片也會一起下載回來。',
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: ready && !_busy ? _restore : null,
                      icon: const Icon(Icons.restore),
                      label: const Text('從 Google 還原'),
                    ),
                    const Divider(height: 28),
                    Text('配對碼', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text('換新手機時，在新手機輸入這組配對碼，就能接手同一個 Google 備份。建議存在密碼管理或記事本裡。',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.5)),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: SelectableText(settings.pairKey,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                        ),
                        IconButton(
                          tooltip: '複製配對碼',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: settings.pairKey));
                            _snack('配對碼已複製');
                          },
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                    TextButton(onPressed: _enterPairKey, child: const Text('輸入舊手機的配對碼')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: '第一次設定（只要做一次）',
                subtitle: '建議在電腦上做',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _step(context, '1', '取得程式碼',
                        '在電腦打開 GitHub 上的 google/Code.gs（或按下面按鈕複製）。'),
                    Wrap(spacing: 8, children: <Widget>[
                      OutlinedButton.icon(
                          onPressed: _copyScript, icon: const Icon(Icons.copy, size: 18), label: const Text('複製程式碼')),
                      OutlinedButton.icon(
                          onPressed: () => _open('https://github.com/Broooooook/life-milestones/blob/main/google/Code.gs'),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('GitHub')),
                    ]),
                    _step(context, '2', '建立 Apps Script',
                        '到 script.google.com →「新專案」→ 刪掉原本內容、貼上程式碼 → 儲存。'),
                    _step(context, '3', '部署成網頁應用程式',
                        '右上「部署」→「新增部署作業」→ 類型選「網頁應用程式」；執行身分「我」、誰可以存取「所有人」→ 部署 → 依畫面授權（看到未驗證提示時按「進階」→「前往」）。'),
                    _step(context, '4', '貼上網址',
                        '複製「網頁應用程式網址」（結尾是 /exec），傳到手機貼在下面，按「儲存並測試」。'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(hintText: 'https://script.google.com/macros/s/…/exec'),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _run(_saveAndTest),
                        child: const Text('儲存並測試'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('第一次測試時，這支手機會和你的 Apps Script 配對，之後其他人就算拿到網址也無法寫入。',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.5)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _step(BuildContext context, String n, String title, String body) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 12,
            backgroundColor: cs.primary,
            child: Text(n, style: TextStyle(fontSize: 12, color: cs.onPrimary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
