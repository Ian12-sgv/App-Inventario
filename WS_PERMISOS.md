# Permisos en tiempo real (WebSocket)

El app se conecta automáticamente al Socket.IO del backend en:

`/ws`

Cuando el administrador cambia permisos/roles de un usuario, el backend envía un evento `auth.me` y la app actualiza roles/permisos sin cerrar sesión.

## Dependencia

Se añadió:

- `socket_io_client`

Luego de actualizar el código:

```bash
flutter pub get
```
