import 'package:flutter/material.dart';

import '../store.dart';
import '../lock.dart';
import '../models.dart';
import '../widgets.dart';
import 'export_page.dart';
import 'overview.dart' show confirmClearSamples;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[settings, store]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        Widget header(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
              child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: <Widget>[
            Text('生涯里程・設定', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text('設定', style: yearStyle(context, 28)),
            header('外觀'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('佈景主題'),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeChoice>(
                        segments: const <ButtonSegment<ThemeChoice>>[
                          ButtonSegment<ThemeChoice>(value: ThemeChoice.paper, label: Text('紙感淺色'), icon: Icon(Icons.light_mode_outlined)),
                          ButtonSegment<ThemeChoice>(value: ThemeChoice.dark, label: Text('深色'), icon: Icon(Icons.dark_mode_outlined)),
                          ButtonSegment<ThemeChoice>(value: ThemeChoice.system, label: Text('跟系統')),
                        ],
                        selected: <ThemeChoice>{settings.theme},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => settings.setTheme(s.first),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('強調色'),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        for (var i = 0; i < accentColors.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Semantics(
                              label: accentNames[i],
                              selected: settings.accent == i,
                              button: true,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => settings.setAccent(i),
                                child: Column(
                                  children: <Widget>[
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: accentColors[i],
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: settings.accent == i ? cs.onSurface : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      child: settings.accent == i
                                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                                          : null,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(accentNames[i], style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        const Expanded(child: Text('字型大小')),
                        Text('${(settings.fontScale * 100).round()}%', style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                    Slider(
                      value: settings.fontScale,
                      min: 0.85,
                      max: 1.4,
                      divisions: 11,
                      label: '${(settings.fontScale * 100).round()}%',
                      onChanged: settings.setFontScale,
                    ),
                    Text('預覽：2008/02/19 更換四顆輪胎',
                        style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            header('顯示'),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: const Text('出生年月（年齡軸）'),
                    subtitle: Text(settings.birthDate == null
                        ? '設定後，總覽和時間軸會顯示每年幾歲'
                        : '${settings.birthDate!.format()}・今年 ${settings.ageIn(DateTime.now().year)} 歲'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final c = TextEditingController(text: settings.birth);
                      final v = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('出生年月'),
                          content: TextField(
                            controller: c,
                            autofocus: true,
                            keyboardType: TextInputType.datetime,
                            decoration: const InputDecoration(hintText: '例如 1977/5 或 1977'),
                          ),
                          actions: <Widget>[
                            TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('清除')),
                            FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('儲存')),
                          ],
                        ),
                      );
                      if (v == null) return;
                      if (v.trim().isNotEmpty && parseSmartDate(v) == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('日期看不懂，請用 1977/5 這種格式')));
                        }
                        return;
                      }
                      settings.setBirth(v);
                    },
                  ),
                  ListTile(
                    title: const Text('時間軸裡的事件順序'),
                    subtitle: Text(settings.timelineNewestFirst ? '新的在上面（12 月 → 1 月）' : '舊的在上面（1 月 → 12 月）'),
                    trailing: SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(value: false, label: Text('舊→新')),
                        ButtonSegment<bool>(value: true, label: Text('新→舊')),
                      ],
                      selected: <bool>{settings.timelineNewestFirst},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => settings.setTimelineNewestFirst(s.first),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('總覽從最新的年份開始'),
                    value: settings.newestFirst,
                    onChanged: settings.setNewestFirst,
                  ),
                  ListTile(
                    title: const Text('開啟 APP 時顯示'),
                    trailing: DropdownButton<int>(
                      value: settings.startTab == 1 ? 1 : 0,
                      underline: const SizedBox.shrink(),
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem<int>(value: 0, child: Text('總覽')),
                        DropdownMenuItem<int>(value: 1, child: Text('時間軸')),
                      ],
                      onChanged: (v) => settings.setStartTab(v ?? 0),
                    ),
                  ),
                ],
              ),
            ),
            header('資料'),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: const Text('事件總數'),
                    trailing: Text('${store.events.length} 筆'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('匯出到 Google 文件／試算表'),
                    subtitle: Text(settings.exportUrl.isEmpty ? '尚未設定' : '已設定・單向備份'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const ExportPage()),
                    ),
                  ),
                  if (store.hasSamples)
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('清除範例資料'),
                      subtitle: const Text('只刪除範例，不影響你自己的事件'),
                      onTap: () => confirmClearSamples(context),
                    ),
                  ListTile(
                    leading: const Icon(Icons.photo_outlined),
                    title: const Text('照片'),
                    trailing: Text('${store.events.fold<int>(0, (a, e) => a + e.photos.length)} 張'),
                  ),
                ],
              ),
            ),
            header('安全'),
            const _SecurityCard(),
            header('關於'),
            Card(
              child: ListTile(
                title: const Text('生涯里程'),
                subtitle: const Text('版本 1.2.0・開源專案 github.com/Broooooook/life-milestones'),
                trailing: Icon(Icons.info_outline, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }
}


/// 安全：APP 上鎖
class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  static const Map<int, String> _timeouts = <int, String>{
    0: '離開就上鎖',
    60: '離開 1 分鐘後',
    300: '離開 5 分鐘後',
    900: '離開 15 分鐘後',
  };

  Future<void> _turnOn(BuildContext context) async {
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const PinSetupPage()),
    );
    if (pin == null) return;
    await appLock.enable(pin);
    if (!context.mounted) return;
    if (await appLock.canUseBiometric() && context.mounted) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('也用指紋或臉部解鎖？'),
          content: const Text('之後可以用指紋／臉部快速解鎖，APP 密碼仍然隨時可用。'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('不用')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('好')),
          ],
        ),
      );
      if (yes == true) await _turnOnBio(context);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已開啟 APP 上鎖')));
    }
  }

  Future<void> _turnOnBio(BuildContext context) async {
    if (!await appLock.canUseBiometric()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('這支手機沒有設定指紋或臉部辨識')));
      }
      return;
    }
    // 先實際驗證一次，確定可以用才打開
    if (await appLock.authBiometric()) {
      await appLock.setBiometric(true);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('沒有驗證成功，先不開啟')));
    }
  }

  Future<bool> _verify(BuildContext context, String title) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => PinVerifyPage(title: title)),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: appLock,
      builder: (context, _) => Card(
        child: Column(
          children: <Widget>[
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: const Text('APP 上鎖'),
              subtitle: Text(appLock.enabled
                  ? (appLock.biometric ? 'APP 密碼＋指紋／臉部' : 'APP 密碼')
                  : '開啟 APP 時要輸入密碼'),
              value: appLock.enabled,
              onChanged: (v) async {
                if (v) {
                  await _turnOn(context);
                } else if (await _verify(context, '關閉上鎖')) {
                  await appLock.disable();
                }
              },
            ),
            if (appLock.enabled) ...<Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('指紋／臉部解鎖'),
                value: appLock.biometric,
                onChanged: (v) async {
                  if (v) {
                    await _turnOnBio(context);
                  } else {
                    await appLock.setBiometric(false);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('自動上鎖'),
                trailing: DropdownButton<int>(
                  value: _timeouts.containsKey(appLock.timeoutSec) ? appLock.timeoutSec : 60,
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<int>>[
                    for (final e in _timeouts.entries) DropdownMenuItem<int>(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => appLock.setTimeout(v ?? 60),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('變更 APP 密碼'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (!await _verify(context, '變更密碼') || !context.mounted) return;
                  final pin = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(builder: (_) => const PinSetupPage()),
                  );
                  if (pin != null) await appLock.changePin(pin);
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_clock_outlined),
                title: const Text('立即上鎖'),
                onTap: appLock.lockNow,
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text(
                '提醒：忘記 APP 密碼就打不開，只能移除重裝（手機上的資料會消失，但 Google 備份裡的內容還在）。',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
