import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// Conexión Socket.IO para recibir cambios de permisos en tiempo real.
///
/// Backend: namespace `/ws`.
class RealtimeSocket {
  final String baseUrl;
  final String token;

  final void Function(Map<String, dynamic> authMe) onAuthMe;
  final void Function() onDeactivated;

  io.Socket? _socket;
  StreamSubscription? _sub;

  RealtimeSocket({
    required this.baseUrl,
    required this.token,
    required this.onAuthMe,
    required this.onDeactivated,
  });

  bool get isConnected => _socket?.connected == true;

  void connect() {
    disconnect();

    final uri = '$baseUrl/ws';

    final s = io.io(
      uri,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          // auth token (socket.io handshake)
          .setAuth({'token': token})
          // respaldo por header
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(500)
          .setReconnectionDelayMax(2000)
          .build(),
    );

    _socket = s;

    s.on('auth.me', (data) {
      if (data is Map) {
        onAuthMe(data.cast<String, dynamic>());
      }
    });

    s.on('user.deactivated', (_) {
      onDeactivated();
    });

    // Si el socket se reconecta, el backend vuelve a meter el cliente al room.
    // No necesitamos polling; si quieres, aquí podríamos pedir /auth/me.

    s.connect();
  }

  void disconnect() {
    try {
      _sub?.cancel();
    } catch (_) {}
    _sub = null;
    final s = _socket;
    _socket = null;
    try {
      s?.dispose();
    } catch (_) {
      try {
        s?.disconnect();
      } catch (_) {}
    }
  }
}
