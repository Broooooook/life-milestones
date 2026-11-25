import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'export.dart';
import 'lock.dart';
import 'models.dart';
import 'screens/edit_event.dart';
import 'screens/overview.dart';
import 'screens/settings_page.dart';
import 'screens/stats.dart';
import 'screens/timeline.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  await appLock.load();
  runApp(const LifeApp());
  await store.load();
  maybeAutoExport();
}

const Color paperBg = Color(0xFFF6F3EC);
const Color paperCard = Color(0xFFFFFFFF);
const Color inkText = Color(0xFF1D1B18);

ThemeData buildTheme(Brightness b, Color accent) {
  final dark = b == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b);
  if (!dark) {
    scheme = scheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      surface: paperBg,
      onSurface: inkText,
      surfaceContainerLowest: paperCard,
      surfaceContainerLow: const Color(0xFFFBF9F4),
      surfaceContainer: const Color(0xFFEFEADF),
      surfaceContainerHigh: const Color(0xFFEAE4D7),
      surfaceContainerHighest: const Color(0xFFE2DBCC),
      outlineVariant: const Color(0xFFDDD6C8),
      onSurfaceVariant: const Color(0xFF6B655B),
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      color: dark ? scheme.surfaceContainerHigh : paperCard,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? scheme.surfaceContainer : paperCard,
      indicatorColor: accent.withAlpha(dark ? 90 : 36),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: scheme.onSurface),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainerHigh : paperCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

class LifeApp extends StatelessWidget {
  const LifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[settings, appLock]),
      builder: (context, _) {
        final mode = switch (settings.theme) {
          ThemeChoice.paper => ThemeMode.light,
          ThemeChoice.dark => ThemeMode.dark,
          ThemeChoice.system => ThemeMode.system,
        };
        return MaterialApp(
          title: '生涯里程',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light, settings.accentColor),
          darkTheme: buildTheme(Brightness.dark, settings.accentColor),
          themeMode: mode,
          locale: const Locale('zh', 'TW'),
          supportedLocales: const <Locale>[Locale('zh', 'TW'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(settings.fontScale),
            ),
            child: Stack(
              children: <Widget>[
                child ?? const SizedBox.shrink(),
                if (appLock.locked) const Positioned.fill(child: LockScreen()),
              ],
            ),
          ),
          home: const HomeShell(),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = settings.startTab == 1 ? 1 : 0;
  int? _year;
  bool _expanded = false;
  String? _focusId;

  void _openYear(int y, {String? focusId}) {
    setState(() {
      _year = y;
      _tab = 1;
      _expanded = false;
      _focusId = focusId;
    });
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<LifeEvent>(
      MaterialPageRoute<LifeEvent>(builder: (_) => const EditEventPage()),
    );
    if (saved != null && mounted) _openYear(saved.start.y, focusId: saved.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (store.loadError != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('讀取資料失敗：${store.loadError}'),
              ),
            ),
          );
        }
        final years = store.years;
        final year = _year ?? (years.isEmpty ? DateTime.now().year : years.last);
        final pages = <Widget>[
          OverviewPage(onOpenYear: (y) => _openYear(y), onOpenEvent: (y, id) => _openYear(y, focusId: id)),
          TimelinePage(
            year: year,
            expandAll: _expanded,
            focusId: _focusId,
            onYearChanged: (y) => _year = y,
            onOpenYear: (y, id) => _openYear(y, focusId: id),
            onToggleExpandAll: () => setState(() => _expanded = !_expanded),
          ),
          const StatsPage(),
          const SettingsPage(),
        ];
        return Scaffold(
          body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: pages)),
          floatingActionButton: _tab <= 1
              ? FloatingActionButton(
                  onPressed: _add,
                  tooltip: '新增事件',
                  child: const Icon(Icons.add),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: '總覽'),
              NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: '時間軸'),
              NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: '統計'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '設定'),
            ],
          ),
        );
      },
    );
  }
}
