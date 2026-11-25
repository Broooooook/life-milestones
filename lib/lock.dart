import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// APP 上鎖：APP 專用密碼（4–6 位數字）一定有，指紋／臉部是可選的捷徑。
/// 密碼只存加鹽雜湊，不存原文。
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  SharedPreferences? _p;
  final LocalAuthentication _auth = LocalAuthentication();

  bool enabled = false;
  bool biometric = false;
  int timeoutSec = 60;
  int pinLength = 4;
  String _hash = '';
  String _salt = '';

  bool locked = false;
  DateTime? _pausedAt;
  bool _suspend = false;
  int _fails = 0;
  DateTime? lockoutUntil;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      _hash = _p!.getString('lockHash') ?? '';
      _salt = _p!.getString('lockSalt') ?? '';
      enabled = (_p!.getBool('lockEnabled') ?? false) && _hash.isNotEmpty;
      biometric = _p!.getBool('lockBiometric') ?? false;
      timeoutSec = _p!.getInt('lockTimeout') ?? 60;
      pinLength = _p!.getInt('lockPinLength') ?? 4;
    } catch (_) {}
    locked = enabled;
    WidgetsBinding.instance.addObserver(this);
  }

  String _h(String pin) => sha256.convert(utf8.encode('$_salt:$pin')).toString();

  Future<void> _savePin(String pin) async {
    final r = Random.secure();
    _salt = List<String>.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _hash = _h(pin);
    pinLength = pin.length;
    await _p?.setString('lockSalt', _salt);
    await _p?.setString('lockHash', _hash);
    await _p?.setInt('lockPinLength', pinLength);
  }

  bool get isLockedOut => lockoutUntil != null && DateTime.now().isBefore(lockoutUntil!);

  bool verifyPin(String pin) {
    if (isLockedOut) return false;
    if (_hash.isNotEmpty && _h(pin) == _hash) {
      _fails = 0;
      return true;
    }
    _fails++;
    if (_fails >= 5) {
      _fails = 0;
      lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    notifyListeners();
    return false;
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  void lockNow() {
    if (!enabled) return;
    locked = true;
    notifyListeners();
  }

  Future<void> enable(String pin) async {
    await _savePin(pin);
    enabled = true;
    await _p?.setBool('lockEnabled', true);
    notifyListeners();
  }

  Future<void> changePin(String pin) async {
    await _savePin(pin);
    notifyListeners();
  }

  Future<void> disable() async {
    enabled = false;
    biometric = false;
    _hash = '';
    await _p?.setBool('lockEnabled', false);
    await _p?.setBool('lockBiometric', false);
    await _p?.remove('lockHash');
    await _p?.remove('lockSalt');
    notifyListeners();
  }

  Future<void> setBiometric(bool v) async {
    biometric = v;
    await _p?.setBool('lockBiometric', v);
    notifyListeners();
  }

  Future<void> setTimeout(int sec) async {
    timeoutSec = sec;
    await _p?.setInt('lockTimeout', sec);
    notifyListeners();
  }

  /// 開相簿、相機、瀏覽器之前呼叫：回來時不要上鎖
  void suspendOnce() => _suspend = true;

  Future<bool> canUseBiometric() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authBiometric() async {
    try {
      _suspend = true;
      return await _auth.authenticate(
        localizedReason: '解鎖生涯里程',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!_suspend) _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (_suspend) {
        _suspend = false;
        return;
      }
      if (enabled && !locked && at != null && DateTime.now().difference(at).inSeconds >= timeoutSec) {
        locked = true;
        notifyListeners();
      }
    }
  }
}

final AppLock appLock = AppLock();

/// 數字鍵盤（上鎖畫面與設定密碼共用）
class PinPad extends StatefulWidget {
  final String title;
  final String? subtitle;

  /// 有值：輸入到這個長度自動送出；null：顯示「完成」鍵（4–6 位）
  final int? autoLength;
  final Future<bool> Function(String pin) onSubmit;
  final Widget? extraKey;
  const PinPad({
    super.key,
    required this.title,
    this.subtitle,
    this.autoLength,
    required this.onSubmit,
    this.extraKey,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _wrong = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.onSubmit(_pin);
    if (!mounted) return;
    if (!ok) {
      HapticFeedback.heavyImpact();
      setState(() {
        _wrong = true;
        _pin = '';
      });
    }
    setState(() => _busy = false);
  }

  void _tap(String d) {
    if (_pin.length >= 6 || _busy) return;
    setState(() {
      _pin += d;
      _wrong = false;
    });
    HapticFeedback.selectionClick();
    if (widget.autoLength != null && _pin.length == widget.autoLength) _submit();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Widget _key(BuildContext context, Widget child, VoidCallback? onTap, {String? label}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      height: 76,
      child: Material(
        color: onTap == null ? Colors.transparent : cs.surfaceContainerHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Semantics(label: label, button: true, child: Center(child: child)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dots = widget.autoLength ?? 6;
    final digit = (String d) => _key(
          context,
          Text(d, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: cs.onSurface)),
          () => _tap(d),
          label: d,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          _wrong ? '密碼不正確，再試一次' : (widget.subtitle ?? ''),
          style: TextStyle(fontSize: 13, color: _wrong ? cs.error : cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < dots; i++)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? cs.primary : Colors.transparent,
                  border: Border.all(color: i < _pin.length ? cs.primary : cs.outline, width: 1.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        for (final row in <List<String>>[
          <String>['1', '2', '3'],
          <String>['4', '5', '6'],
          <String>['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final d in row) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: digit(d)),
              ],
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: widget.autoLength == null
                  ? _key(
                      context,
                      Text('完成',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _pin.length >= 4 ? cs.primary : cs.onSurfaceVariant)),
                      _pin.length >= 4 ? _submit : null,
                      label: '完成',
                    )
                  : (widget.extraKey ?? const SizedBox(width: 76, height: 76)),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: digit('0')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _key(context, Icon(Icons.backspace_outlined, color: cs.onSurface), _back, label: '刪除'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 上鎖畫面（蓋在整個 APP 上面）
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    if (appLock.biometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
    }
  }

  Future<void> _bio() async {
    if (await appLock.authBiometric()) appLock.unlock();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.lock_outline, size: 36, color: cs.primary),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: appLock,
                  builder: (context, _) => PinPad(
                    title: '生涯里程',
                    subtitle: appLock.isLockedOut ? '錯誤太多次，請 30 秒後再試' : '輸入 APP 密碼',
                    autoLength: appLock.pinLength,
                    onSubmit: (pin) async {
                      if (appLock.verifyPin(pin)) {
                        appLock.unlock();
                        return true;
                      }
                      return false;
                    },
                    extraKey: appLock.biometric
                        ? SizedBox(
                            width: 76,
                            height: 76,
                            // 上鎖畫面在 Navigator 外面，沒有 Overlay，所以不能用 tooltip
                            child: IconButton(
                              onPressed: _bio,
                              icon: Icon(Icons.fingerprint, size: 36, color: cs.primary, semanticLabel: '用指紋或臉部解鎖'),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 設定新密碼（輸入兩次）。成功時 pop 回傳密碼。
class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key});

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  String? _first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定 APP 密碼')),
      body: Center(
        child: SingleChildScrollView(
          child: PinPad(
            key: ValueKey<bool>(_first == null),
            title: _first == null ? '輸入新密碼' : '再輸入一次',
            subtitle: _first == null ? '4 到 6 位數字，輸入完按「完成」' : '確認剛剛的密碼',
            autoLength: _first?.length,
            onSubmit: (pin) async {
              if (_first == null) {
                setState(() => _first = pin);
                return true;
              }
              if (pin == _first) {
                Navigator.of(context).pop(pin);
                return true;
              }
              return false;
            },
          ),
        ),
      ),
    );
  }
}

/// 確認目前密碼。成功 pop(true)
class PinVerifyPage extends StatelessWidget {
  final String title;
  const PinVerifyPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          child: PinPad(
            title: '輸入目前的密碼',
            autoLength: appLock.pinLength,
            onSubmit: (pin) async {
              if (appLock.verifyPin(pin)) {
                Navigator.of(context).pop(true);
                return true;
              }
              return false;
            },
          ),
        ),
      ),
    );
  }
}
