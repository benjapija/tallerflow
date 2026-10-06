# Supabase de pruebas · desarrollo actual

Proyecto gpseuqmzbazifmkhjyby conectado, plan Free confirmado. Migraciones 001–005 y función workshop-members desplegadas. Taller ficticio 1987c4ef-9612-4b27-b4f2-117364fe231e. La primera pertenencia administradora espera confirmación de la identidad del correo; no se concede acceso por aproximación del nombre. No hay llamadas de IA ni claves privadas en Flutter.

## Configuración desde el Mac

1. Utiliza el proyecto conectado solo con datos ficticios. Para otro entorno, crea un proyecto independiente.
2. En una base nueva aplica las migraciones de supabase/migrations en orden. En una base existente aplica solo las nuevas. Despliega supabase/functions/workshop-members/index.ts y handler.ts con verify_jwt=true. El entorno de pruebas conectado ya tiene estas cinco migraciones.
3. Mantén expuesto solo `public` en la Data API; no expongas `private`. No concedas escritura directa a tablas.
4. La primera cuenta administradora la crea el propietario del proyecto en Authentication → Users y se vincula por su UUID exacto mediante el bootstrap. Las posteriores se crean desde Configuración → Administración → Crear cuenta. El servicio exige administrador activo, dispositivo y sesión vigentes. Cada persona utiliza sus propias credenciales.
5. config/pilot.public.json contiene solo URL, clave publicable y taller de pruebas. Es información pública de cliente y no otorga acceso sin Auth. Para otra instalación puedes usar client-config.json, excluido de Git:

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

## Administración y recuperación

Tarifas, impuestos, permisos, catálogo y plantillas versionadas se editan desde Configuración con motivo, revisión y auditoría. La función workshop-members usa exclusivamente una clave de servicio del entorno del servidor. El cliente conserva el ID y los datos no secretos de una solicitud incierta; al reintentar no crea otra identidad ni cambia su contraseña. Archivar una solicitud conserva evidencia y no borra cuentas.

La copia portable cifrada incorpora servidor y dispositivo, pendientes, documentos, auditoría, gestión y solicitudes de alta sin credenciales. La restauración exige taller aislado, nueva identidad de dispositivo y UUID Auth originales; retira dispositivos históricos e invalida cierres activos. Fotos/Storage, recuperación Auth entre proyectos y uso de archivos nativos siguen pendientes. La función de altas mantiene autentificación JWT y comprueba también el usuario contra Auth antes de preparar solicitudes. Referencia: https://supabase.com/docs/guides/functions/auth-headers

Referencia de las funciones y permisos: [funciones de base de datos de Supabase](https://supabase.com/docs/guides/database/functions).
