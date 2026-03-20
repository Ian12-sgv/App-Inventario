import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/shell.dart';

class UserAppViewScreen extends StatelessWidget {
  const UserAppViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await context.read<AppState>().stopImpersonation();
        return true;
      },
      child: const Material(
        color: AppTheme.bg,
        child: AppShell(),
      ),
    );
  }
}
