# Supabase de pruebas · desarrollo actual

Proyecto gpseuqmzbazifmkhjyby conectado, plan Free confirmado. El principal tiene veinticinco migraciones lógicas y funciones workshop-members, workshop-photos, workshop-portal y workshop-ai desplegadas. Taller piloto ficticio 1987c4ef-9612-4b27-b4f2-117364fe231e. La pertenencia administradora corresponde al UUID de ramirezbroja013@gmail.com confirmado por el usuario; no se ha leído su contraseña. El recorrido HTTP real se validó en otros dos talleres ficticios, ahora sin cuentas ni dispositivos activos.

## Configuración desde el Mac

1. Utiliza el proyecto conectado solo con datos ficticios. Para otro entorno, crea un proyecto independiente.
2. En una base nueva aplica las migraciones de supabase/migrations en orden. En una base existente aplica solo las nuevas. Despliega las funciones workshop-members y workshop-photos (index.ts y handler.ts) con verify_jwt=true. El entorno de pruebas conectado ya tiene estas migraciones.
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

6. Compila el cliente conectado para Windows en GitHub Actions, o para un simulador/móvil autorizado desde el Mac. No se prepara una aplicación macOS. Para Android, con su SDK disponible:

```sh
flutter run -d ID_ANDROID --dart-define-from-file=config/pilot.public.json
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
| `management_command(...)` | Configuración, usuarios, catálogo y plantillas con revisión y auditoría |
| `vehicle_command(...)` | Matrícula y propietario; conserva identidad estable, alias y destinatarios históricos |
| `export_workshop(...)` / `restore_workshop(...)` | Archivo de las tablas permitidas; recuperación aislada |

Acciones de fiabilidad: `request_close`, `ack_close`, `issue`, `resolve`, `retire_device`, `end_retired_timer` y `replace_device`. La operación antigua `issue` permanece prohibida. `workshop_snapshot` se conserva como lectura compatible, pero no concede inscripción de dispositivos ni permiso para saltarse el protocolo.

El servidor usa el usuario autenticado y su pertenencia, y comprueba el identificador de sesión del JWT contra `auth.sessions`. Las sesiones históricas de un equipo retirado se conservan vinculadas para impedir eludir su retirada. Las pruebas HTTP confirmaron sesiones reales, aislamiento, concurrencia, cierre y denegación después de cerrar sesión; el uso nativo continúa pendiente.

## Prueba de tres equipos

La misma cuenta usada en dos equipos debe obtener sesiones independientes; no copies tokens ni almacenes de otro equipo. Prepara dos operarios asignados a una orden y una oficina. Descarga la orden en los tres. Desconecta uno, registra tiempo y consumo y reinícialo físicamente. Comprueba que el cierre normal no es posible hasta reconciliarlo.

Repite con confirmación obsoleta, respuesta perdida, conflicto de stock, retirada y recuperación. Cerrar una sesión debe afectar al equipo actual; el cliente usa cierre de sesión local. Una sesión nueva en un equipo activo invalida confirmaciones afectadas antes de revalidar su identidad.

Las retiradas requieren otro equipo de oficina o administrador. La sustitución requiere credenciales de la misma cuenta para una sesión nueva; no se guardan en la cola de comandos. Un equipo retirado puede recuperar registros como incidencias, pero no modificará documentos emitidos.

Para una instalación 0.1 anterior sin vínculos de sesión, utiliza un entorno de pruebas y una migración supervisada: revoca las sesiones antiguas en Auth y revalida los equipos antes de utilizar el protocolo. No hay una instalación alojada previa de este proyecto.

## Administración y recuperación

Tarifas, impuestos, permisos, catálogo y plantillas versionadas se editan desde Configuración con motivo, revisión y auditoría. La función workshop-members usa exclusivamente una clave de servicio del entorno del servidor. El cliente conserva el ID y los datos no secretos de una solicitud incierta; al reintentar no crea otra identidad ni cambia su contraseña. Archivar una solicitud conserva evidencia y no borra cuentas.

La copia cifrada dividida incorpora servidor y dispositivo, pendientes, documentos, auditoría, gestión y fotografías; excluye credenciales de Auth. [COPIAS_Y_RECUPERACION.md](COPIAS_Y_RECUPERACION.md) detalla límites y recuperación. La restauración exige un taller vacío, UUID originales y una identidad nueva de dispositivo. Se comprobaron 36 MiB de fotos localmente y cinco altas Auth con UUID explícito; la restauración alojada actual formato 13 aprobó nueve comprobaciones adicionales con Auth real.

La lectura de fotografías se realiza exclusivamente con POST `workshop-photos`, acción `read`, UUID de foto/taller/dispositivo y JWT. El servidor consulta `photo_download_info` con la sesión de la persona antes y después de descargar, valida hash/tamaño y responde `application/octet-stream` con `Cache-Control: private, no-store`. No hay políticas SELECT para clientes en Storage, ni URLs firmadas. Se comprobó por HTTP que las operaciones de información de Storage también autorizaban GET y podían alimentar una caché por usuario; las migraciones 011–012 cierran esa vía. Las compilaciones anteriores a este cambio necesitan actualizarse para descargar fotos. Los únicos archivos creados durante la detección fueron tres JPEG ficticios (1857 bytes) en talleres de prueba ya retirados; sus evidencias y documentos se conservan inmutables.

El servicio temporal de las cinco identidades fue autorizado expresamente, las cuentas quedaron bloqueadas, sus sesiones revocadas, y sus pertenencias/equipos retirados. Los manejadores temporales tallerflow-qa-setup y tallerflow-qa-recovery v4 solo devuelven 410; ya no contiene cliente administrativo ni lee credenciales del entorno. Referencias: [JWT de funciones](https://supabase.com/docs/guides/functions/auth-headers), [CDN de Storage](https://supabase.com/docs/guides/storage/cdn/fundamentals).

Referencia de las funciones y permisos: [funciones de base de datos de Supabase](https://supabase.com/docs/guides/database/functions).

La primera cuenta administradora confirmada es **ramirezbroja013@gmail.com**. Se vinculó con auditoría y sin leer su contraseña; esto no acredita haber iniciado sesión en la aplicación.

## Inspecciones · 7 de octubre

Migración 013 aplicada en el proyecto principal. Seis pruebas Flutter, ocho PostgreSQL locales y diez SQL alojadas aprobaron versiones, reintentos, conflictos, permisos, exportación e historial técnico sin datos del destinatario. Las pruebas SQL alojadas emplearon identidades sintéticas y se revirtieron; no acreditan Auth HTTP ni cámara. Batería completa: 96 Flutter, 130 PostgreSQL y 18 servicios simulados. Analizador limpio.

## Recuperación alojada y retirada · 7 de octubre

Diez comprobaciones HTTP reales entre gpseuqmzbazifmkhjyby y qnbgbgumvxmmipjlkcgb (Free, coste confirmado 0 USD/mes). Dos UUID Auth originales recreados con contraseñas ficticias distintas. Se conservan documentos, operaciones, auditoría, fotografías originales y versiones de inspección; reintentos no duplican la restauración y los equipos históricos quedan retirados. Cuatro identidades Auth de prueba retiradas, cero sesiones/pertenencias/equipos activos, servicios temporales sustituidos por respuesta 410 y credenciales efímeras eliminadas. El circuito nativo Windows f9aeed3 también pasó fotos/copia/restauración entre dos procesos, con servidor ficticio.

## Portal y agenda actuales

workshop-portal usa verify_jwt=false porque el destinatario no tiene una cuenta de personal. Cada POST exige enlace secreto y código independiente; sus hashes se verifican en el servidor antes de acceder a presupuestos, decisiones o fotos. El servicio utiliza la clave administrativa exclusivamente en su entorno. Personal y anónimos carecen de permisos para invocar customer_portal directamente. Las altas y revocaciones de oficina sí requieren sesión/dispositivo/rol vigentes.

La agenda, mantenimiento, flotas, proyección de decisiones del portal e IA están aplicados en ambos proyectos Free. El usuario autorizó específicamente qnbgbgumvxmmipjlkcgb. Sus cinco migraciones nuevas constan en evidence/current-recovery-schema.json; equivalían a 25 migraciones lógicas, con trece entradas de historial porque el esquema base agrupaba migraciones anteriores. No volver a aplicar una migración equivalente basándose solo en el número de entradas.

El 7 de octubre se repitieron 15 comprobaciones HTTP de fase 1, 12 de módulos y nueve de restauración actual; 83 invariantes SQL de recuperación se ejecutaron con rollback. Se verificaron cinco identidades ficticias por proyecto, originales inmutables, costes por permiso, CSV, presupuestos, cobros, compras, retornos, diagnóstico/biblioteca, agenda/mantenimiento/flotas y aislamiento. Después se retiraron sesiones/pertenencias/dispositivos y ambos servicios temporales (410). Las capacidades efímeras se eliminaron; no reutilizar usuarios o secretos retirados. No se modificó ninguna cuenta real.

workshop-ai mantiene generación desactivada y límite cero por decisión explícita del usuario. La recuperación de borradores ya existentes es separada y nunca reenvía automáticamente una solicitud. El código de la aplicación no contiene claves privadas.

## Preparación fiscal por taller

La migración 026 fiscal_preparation_profiles está aplicada: principal 20261007112840, recuperación 20261007112852. Ambos contienen 26 migraciones lógicas; recuperación tiene 14 entradas de historial por el esquema base agrupado. No repetir una migración por comparar solo esos recuentos.

management_command admite fiscal_profile_save solo para administrador y dispositivo/sesión válidos. Valida opciones/campos, rechaza secretos/activación, serializa revisión, conserva recibo idempotente y audita antes/después/motivo. No altera órdenes, tarifas ni documentos. El perfil permanece en settings, incluido en copias formato 13. Doce SQL con rollback por proyecto alojado; identidades sintéticas, no login HTTP. La revisión de seguridad conserva tablas privadas con RLS sin políticas directas; protección de contraseñas filtradas requiere Pro según Supabase y no se ha contratado.
