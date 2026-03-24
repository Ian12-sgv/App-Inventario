import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'state/app_state.dart';
import 'ui/app_theme.dart';
import 'ui/loading_screen.dart';
import 'ui/shell.dart';
import 'screens/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Necesario para DateFormat(..., 'es')
  await initializeDateFormatting('es', null);

  final model = AppState();

  runApp(ChangeNotifierProvider.value(value: model, child: const MyApp()));

  unawaited(model.init());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mi App',
      theme: AppTheme.light(),

      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final ready = context.select<AppState, bool>((state) => state.ready);
    final busy = context.select<AppState, bool>((state) => state.busy);
    final isLoggedIn = context.select<AppState, bool>(
      (state) => state.isLoggedIn,
    );

    if (!ready) {
      return const Scaffold(
        body: LoadingScreen(message: 'Preparando tu espacio...'),
      );
    }

    final child = isLoggedIn ? const AppShell() : const LoginScreen();

    if (!busy) {
      return child;
    }

    return Stack(
      children: [
        AbsorbPointer(child: child),
        const BlockingLoadingOverlay(
          message: 'Sincronizando tu informacion...',
        ),
      ],
    );
  }
}
