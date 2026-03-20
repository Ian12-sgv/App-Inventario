import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Muestra un diálogo de confirmación y cierra sesión.
Future<void> confirmLogout(BuildContext context) async {
  final state = context.read<AppState>();
  final isModoUsuario = state.isImpersonating;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isModoUsuario ? 'Salir de vista de usuario' : 'Cerrar sesión'),
      content: Text(
        isModoUsuario
            ? 'Volverás a tu sesión de administrador.'
            : '¿Seguro que quieres cerrar sesión?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(isModoUsuario ? 'Salir' : 'Cerrar sesión'),
        ),
      ],
    ),
  );

  if (ok != true) return;
  if (isModoUsuario) {
    await state.stopImpersonation();
    return;
  }
  await state.logout();
}
