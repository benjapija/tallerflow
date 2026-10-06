# Supabase de pruebas · 0.2

No se ha creado ni conectado un proyecto alojado. Las pruebas ejecutan ambas migraciones en PostgreSQL/PGlite con Auth y sesiones simulados. No hay claves privadas ni llamadas de IA en esta entrega.

## Configuración desde el Mac

1. Crea un proyecto de pruebas accesible desde el navegador, con datos ficticios.
2. En SQL Editor aplica `supabase/migrations/202610060001_core.sql` y después `202610060002_reliability.sql`. En una base que ya tenga 001, aplica solo 002. Después añade `supabase/seed.sql` si aún no está cargado.
3. Mantén expuesto solo `public` en la Data API; no expongas `private`. No concedas escritura directa a tablas.
4. Crea cuentas individuales en Authentication → Users. No actives registro libre. Usa los ejemplos comentados de `tool/bootstrap_workshop.sql` para vincular sus UUID a administrador, oficina y operarios.
5. Guarda localmente la URL, clave pública/publishable y taller en `client-config.json`, excluido del paquete y de Git:

```json
{
  "SUPABASE_URL": "https://TU_PROYECTO.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "TU_CLAVE_PUBLICA",
  "WORKSHOP_ID": "a110fc00-0000-4000-8000-000000000001"
}
```

6. Con Xcode completo disponible, abre la versión nativa desde Mac:

```sh
flutter run -d macos --dart-define-from-file=client-config.json
```

7. Inicia sesión con una cuenta real de **pruebas**. Su primer acceso necesita conexión. A partir de la descarga validada podrá reabrir la caché cifrada durante la vigencia definida.

Nunca incluyas `service_role`, contraseña de base de datos o clave OpenAI en la aplicación o en ese archivo. La demo web rechaza acceso al taller real; el circuito conectado se prueba en clientes nativos.

## APIs utilizadas

| API | Función |
|---|---|
| `my_membership(workshop_id)` | Pertenencia activa y permisos de la cuenta |
| `device_snapshot(workshop_id, device_id)` | Registra identidad/sesión y órdenes descargadas; devuelve estado, recibos, incidencias, cierres y equipos accesibles |
| `apply_operation(workshop_id, device_id, operation)` | Trabajo operativo validado, idempotente y conservado ante conflicto o llegada tardía |
| `reliability_command(workshop_id, device_id, command_id, action, payload)` | Cierre, confirmación, emisión, resolución, retirada, fin real de cronómetro y sustitución |

Acciones de fiabilidad: `request_close`, `ack_close`, `issue`, `resolve`, `retire_device`, `end_retired_timer` y `replace_device`. La operación antigua `issue` permanece prohibida. `workshop_snapshot` se conserva como lectura compatible, pero no concede inscripción de dispositivos ni permiso para saltarse el protocolo.

El servidor usa el usuario autenticado y su pertenencia, y comprueba el identificador de sesión del JWT contra `auth.sessions`. Las sesiones históricas de un equipo retirado se conservan vinculadas para impedir eludir su retirada. Este comportamiento necesita pruebas reales con Supabase Auth, además de las simulaciones guardadas.

## Prueba de tres equipos

La misma cuenta usada en dos equipos debe obtener sesiones independientes; no copies tokens ni almacenes de otro equipo. Prepara dos operarios asignados a una orden y una oficina. Descarga la orden en los tres. Desconecta uno, registra tiempo y consumo y reinícialo físicamente. Comprueba que el cierre normal no es posible hasta reconciliarlo.

Repite con confirmación obsoleta, respuesta perdida, conflicto de stock, retirada y recuperación. Cerrar una sesión debe afectar al equipo actual; el cliente usa cierre de sesión local. Una sesión nueva en un equipo activo invalida confirmaciones afectadas antes de revalidar su identidad.

Las retiradas requieren otro equipo de oficina o administrador. La sustitución requiere credenciales de la misma cuenta para una sesión nueva; no se guardan en la cola de comandos. Un equipo retirado puede recuperar registros como incidencias, pero no modificará documentos emitidos.

Para una instalación 0.1 anterior sin vínculos de sesión, utiliza un entorno de pruebas y una migración supervisada: revoca las sesiones antiguas en Auth y revalida los equipos antes de utilizar el protocolo. No hay una instalación alojada previa de este proyecto.

## Administración y recuperación pendientes

Tarifas, impuestos, catálogo y pertenencias aún se preparan desde servidor: las pantallas administrativas completas siguen pendientes. Los cambios manuales por SQL no equivalen a auditoría de producto completa.

Los archivos/fotos y sus políticas de Storage no están implementados. Falta exportación y restauración completas de base, usuarios pertinentes, archivos, documentos, auditoría y pendientes locales en un entorno separado. La recuperación de un almacén cifrado probada en esta entrega no demuestra esa restauración completa.

Referencia de las funciones y permisos: [funciones de base de datos de Supabase](https://supabase.com/docs/guides/database/functions).
