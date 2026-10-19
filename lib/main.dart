import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/desktop/desktop_home.dart';
import 'ui/quest/quest_home.dart';
import 'ui/shared/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(950, 800),
        minimumSize: Size(700, 650),
        center: true,
        title: 'TransferFiles',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('Error inicializando window_manager: $e');
    }
  }

  runApp(const TransferFilesApp());
}

class TransferFilesApp extends StatelessWidget {
  const TransferFilesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Detectar plataforma para mostrar la interfaz adecuada
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return MaterialApp(
      title: 'TransferFiles',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      theme: AppTheme.getTheme(),
      home: isDesktop ? const DesktopHome() : const QuestHome(),
    );
  }
}
