import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/alarm_store.dart';
import 'pages/home_page.dart';

/// ============================================================
/// 智闹 App 入口
/// ============================================================
void main() {
  // 初始化 Flutter 与原生通道，必须放在 runApp 之前
  WidgetsFlutterBinding.ensureInitialized();

  // 从 SQLite 加载闹钟数据，并同步给原生侧重新排程。
  // 这里不 await，避免数据库慢时白屏；界面会走 loading 分支。
  AlarmStore.instance.init();

  runApp(const ZhinaoApp());
}

class ZhinaoApp extends StatelessWidget {
  const ZhinaoApp({super.key});

  /// 主题种子色：偏冷静的靛蓝，早上醒来不刺眼
  static const _seedColor = Color(0xFF5B6BF5);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智闹',
      debugShowCheckedModeBanner: false,

      // ---- 中文界面 ----
      // 固定中文，让日期选择器、"确定/取消"等系统组件都显示中文
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
