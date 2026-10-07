## Cobros y entrega · 7 de octubre de 2026

117 pruebas Flutter y 149 comprobaciones PostgreSQL/PGlite, más 18 de servicios simulados, aprobadas. Cobros: ocho pruebas Flutter y diez PostgreSQL; restauración de cobro/documento/auditoría entre dos bases independiente ampliada. Pagos parciales, devoluciones parciales vinculadas, concurrencia de dos oficinas, reinicio cifrado, copia local, pérdida de respuesta, sobrepago y permisos comprobados. Diez SQL alojadas por cada proyecto Free, revertidas; no son un inicio de sesión Auth HTTP ni uso manual nativo. Migración 015 desplegada en ambos proyectos.

Paquetes c0f8a74 descargados y verificados: presupuestos con catálogo e IVA corregidos. Todavía no contienen cobros. Las pruebas nativas Windows e iOS simulador anteriores utilizan un servidor ficticio.

# Validación actual · 7 de octubre de 2026

Datos ficticios. No se acredita un piloto real ni una aplicación macOS.

| Entorno | Resultado actual | Límite |
|---|---|---|
| Flutter local | 109 pruebas y analizador limpio | Plugins físicos y piloto manual separados |
| PostgreSQL/PGlite | 139 comprobaciones | Auth sintético |
| Servicios locales | 18 comprobaciones de alta y fotos | Dependencias HTTP simuladas |
| Supabase HTTP real | 15 Auth/fotos/cierre + 10 recuperación entre proyectos | Clientes HTTP de prueba; no sesión personal ni cámara |
| Presupuestos SQL alojado | 10 comprobaciones en cada proyecto, todas revertidas | Auth sintético en SQL; circuito HTTP de presupuestos pendiente |
| Windows nativo | Dos procesos; credenciales, archivos cifrados, fotos y copias por partes aprobados, f9aeed3 / 37553141586 | Servidor ficticio; instalador manual pendiente |
| iOS nativo | Dos procesos del simulador; llavero, archivos cifrados, fotos y restauración con otra clave aprobados, 2ae0b87 / 37555896692 | Simulador, servidor ficticio; no iPhone físico |
| Paquetes compilados | Windows, Android debug e iOS simulador, 23d62b8 / 37554417241; hashes verificados | Incluyen inspecciones; presupuestos integrados requieren la nueva compilación |

Migración 014 de presupuestos aplicada en ambos proyectos. Las versiones y decisiones se incluyen en las órdenes y en las copias completas; las decisiones solo autorizan partidas aceptadas de la versión actual. El rechazo de una ampliación conserva el trabajo previo. Los documentos de presupuesto se excluyen del perfil operario incluso con permiso de precios. Las pruebas locales incluyen reinicio, copia, reintentos, cambios de revisión y autorizaciones parciales.

Las advertencias del asesor siguen siendo las ya registradas: tablas del esquema privado con RLS sin políticas (denegación directa intencional; acceso mediante funciones verificadas) y protección de contraseñas filtradas desactivada. No se ha contratado un plan para cambiar esta última configuración. Referencia de configuración: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.

Los apartados siguientes son históricos: sus cifras, pendientes y fallos corresponden al momento indicado. El resumen de arriba y PENDIENTES.md prevalecen para el estado actual.

# Registro de validaciones anteriores

6 de octubre de 2026. Datos ficticios. Flutter 3.47.6 / Dart 3.13.5. Los registros de 0.2 permanecen en evidence y en su entrega original.

| Entorno | Resultado ejecutado | Límite |
|---|---|---|
| Flutter local | 59 pruebas; analizador sin incidencias | No acredita plugins ni equipos físicos |
| PostgreSQL/PGlite | 16 regresión + 29 fiabilidad + 10 copias + 16 gestión + 9 historial + 10 precios + 7 altas = 97 | Auth y sesiones simulados |
| Función de alta | 6 pruebas con API Auth simulada | No crea usuarios reales durante estas pruebas |
| Supabase alojado | Ocho migraciones y función workshop-members desplegadas; 10 circuito + 7 altas + 11 historial + 10 precios = 38 | Identidades SQL ficticias; se revierte cada transacción |
| Protección de función alojada | Petición sin autorización devuelve 401 | Comprueba denegación, no un alta autenticada |
| GitHub Actions #1 | Validación aprobada; compilaciones Apple correctas; los cuatro trabajos completados | Commit c6f9c09; contiene 38 pruebas Flutter y 69 SQL, anteriores al nuevo servicio de altas |
| Windows remoto | Dos procesos de aplicación reales con Credential Manager y archivo cifrado; dos registros sin conexión recuperados y sincronizados una sola vez | Commit e26a77a, anterior a historial/precios; servidor ficticio, Auth HTTP no validado e instalador sin prueba manual |
| macOS | Compilación antigua generada; lanzamiento rechazado por AMFI por entitlement de llavero sin perfil Apple | Plataforma retirada del alcance por petición del usuario el 6 de octubre; no bloquea la entrega |
| iOS/Android | Compilación de simulador iOS y APK debug aprobadas | Funcionamiento en simuladores y equipos físicos pendiente |
| Auth real | Pendiente de confirmar correo administrador y probar inicio de sesión | No se conocen ni se guardan contraseñas del usuario |

Evidencias actuales: `flutter-tests-current.txt`, `analyzer-current.txt`, `database-tests-current.txt`, `hosted-database-validation.json`, `account-provisioning-validation.json`, `vehicle-and-pricing-validation.json`, `windows-native-validation.json`, `windows-native-validation.zip` y `edge-unauthorized-hosted.txt`. Las migraciones 001–009 se aplican en los bancos de pruebas locales.

Las copias incluyen estado de servidor, documentos inmutables, auditoría, sesiones históricas, cierres, solicitudes de cuentas y el estado local pendiente. El archivo portable está cifrado. Las contraseñas y los tokens Auth se excluyen. La recuperación en otra base requiere las identidades Auth originales; las fotos y sus pendientes se recuperan localmente con hash y clave de dispositivo distinta; copias grandes y recuperación Auth siguen pendientes. Estos límites impiden considerar terminada la recuperación completa.

## Cobertura del bloque solicitado

- Reapertura desde caché cifrada sin consulta previa; cronómetro y cola conservados al reconstruir el cliente.
- Vencimiento de 24 horas, retroceso de reloj, cuenta incorrecta y revocación, con conservación de pendientes.
- Cambios remotos mientras hay conflictos locales, sin duplicar la proyección ni eliminar originales.
- Recibo perdido, confirmación perdida y reintentos con identificadores estables.
- Fallo de disco antes de confirmar y al guardar un recibo: no se confirma sin bloqueo persistente ni se pierde el comando.
- Dos operarios y oficina; un móvil sin confirmar bloquea emisión.
- Confirmación antigua, cambio durante cierre, incorporación de un equipo nuevo e invalidación de solicitudes.
- Consumos simultáneos de la última existencia: el inválido queda conservado para revisión sin stock negativo.
- Resolución con motivo, responsable, corrección nueva y autor original; recibo de resolución en el equipo de origen.
- Retirada con auditoría, recuperación de registros y recepción nunca subida; sustitución con identidad nueva y sesión nueva.
- Bloqueo de todas las sesiones históricas de un equipo retirado y de una sesión eliminada en Auth, con JWT simulado.
- Fin real y justificado de un cronómetro de equipo perdido, conservando su autor.
- Emisión atómica, total determinista, excepción administrativa identificada e inmutabilidad de fila e instantánea de documento.
- Datos tardíos conservados y resolución que no altera documentos emitidos.
- Permisos, acceso anónimo negado, aislamiento de talleres, precios ocultos al operario y RLS.
- Simulación visible de tres dispositivos, navegación móvil sin desbordamiento y restricciones de oficina.

## Pruebas anteriores conservadas

Se mantienen comprobaciones de matrícula/identidad, autorizaciones individuales, tiempos incompatibles y solapados, cantidades decimales, reservas frente a consumo, devoluciones parciales/excesivas, precios conservados, cálculos, guardado atómico y rechazo de cifrado alterado.

## Pendiente antes de piloto

Prueba real entre cuentas de operario y oficina, pérdida de conexión, suspensión/reinicio, concurrencia, permisos de cámara y recuperación de archivos en los clientes conectados. Xcode 27 y una cuenta Apple personal ya están disponibles en el Mac; SDK Android local y equipos físicos pendientes. Windows se ha ejecutado en el entorno remoto de GitHub Actions, pero falta probar el instalador y el circuito con Auth real. Ya no se solicita una aplicación macOS.

Historial y revisión de precios están implementados y comprobados localmente y en SQL alojado. El propietario actual no sustituye al destinatario de reparaciones anteriores; el historial de operarios omite destinatarios y documentos personales. Aumentos de precio/impuesto, reducción de descuento y volver a cobrar invalidan la autorización anterior y conservan su evidencia. Descuentos y consumos sin cobro se calculan antes del impuesto; el movimiento y el coste permanecen. El margen es estimado y señala costes desconocidos. Storage HTTP real, cámara/QR físicos, copias grandes, recuperación Auth y las fases siguientes permanecen abiertos en PENDIENTES.md.

El asesor de seguridad de Supabase comunica 28 avisos informativos de tablas privadas con RLS sin políticas directas: la denegación es deliberada y las APIs autorizadas controlan su acceso. También señala que la protección de contraseñas filtradas está desactivada; Supabase la reserva para Pro o superior. Se conserva Free y no se ha contratado un plan. Referencias: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [contraseñas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Los datos fiscales y las fuentes técnicas requieren confirmación antes de completar sus módulos.

## Fotos y enlaces · último avance

69 pruebas Flutter, 109 comprobaciones PostgreSQL locales y 14 pruebas de servicios con dependencias simuladas aprobadas. Analizador sin incidencias. Fotos: 6 pruebas Flutter, 12 PostgreSQL (incluida otra base de recuperación), 8 del verificador simulado y 10 SQL alojadas en transacción revertida. QR: 4 pruebas del analizador estricto y acceso por órdenes permitidas.

Se comprueban hash, cifrado, reinicio, respuesta perdida, disco lleno, archivo ausente, permisos, denegación de sustitución/borrado y URL firmada, retirada, revisión de oficina y bloqueo del cierre mientras faltan archivos. El fallo de revisión detectado en pruebas se corrigió usando la revisión de la fila autoritativa. La verificación HTTP real de Storage, las sesiones Auth reales, los permisos físicos de cámara y los enlaces del sistema siguen pendientes. Las compilaciones históricas no contienen estos cambios.

## CSV y compilaciones · 7 de octubre de 2026

77 pruebas Flutter, 121 comprobaciones PostgreSQL locales y 14 de servicios simulados aprobadas; analizador sin incidencias. CSV añade 8 Flutter (incluido cambio de perfil en pantalla), 12 PostgreSQL y 10 SQL alojadas con transacción revertida: total alojado 58. La migración 010 está aplicada. Clientes conservan código e identidad; vehículos se vinculan a clientes sin crear reparaciones; referencias existentes no cambian precios ni existencias. El reintento de un lote conserva resultado y auditoría y rechaza reutilizar su ID con datos diferentes.

El commit fa876b0ac0bf11cbde6cd82b0ddcbaab121eb353 compila Windows con instalador, Android debug e iOS para simulador en el run 37540024104. La prueba nativa de Windows del run 37541988376 ha aprobado guardado sin conexión y recuperación en otro proceso; sigue usando servidor ficticio. Los ZIP descargados se verificaron contra los hashes de los artefactos. Estas compilaciones incluyen fotos/QR/historial/precios; todavía no incluyen CSV.

Las referencias históricas de este documento conservan sus cifras y versiones originales. Auth HTTP, Storage HTTP, cámaras físicas, selección nativa de CSV y recuperación Auth entre proyectos siguen pendientes.


## Copias divididas y Auth/Storage HTTP · 7 de octubre de 2026

90 Flutter aprobadas en el Mac (84 previas + 2 de fotos históricas + 4 de reintento Storage); las cuatro se repitieron después de sustituir GET por el POST privado. Analizador sin incidencias. 122 PostgreSQL/PGlite y 18 de servicios simulados aprobadas; tras retirar la política de lectura directa se repitieron las 13 de fotos. Siete pruebas del conjunto cifrado verifican una copia de 36 MiB, lectura de un original cada vez, claves distintas, archivos ausentes/mezclados/manipulados, contraseña incorrecta, fallos de escritura y conservación de pendientes e identidades originales. La derivación rápida de esos siete casos es solo de prueba; la producción conserva PBKDF2 de 600.000 iteraciones comprobado por backup_test.

Supabase real: 15 comprobaciones HTTP aprobadas con cinco cuentas creadas mediante GoTrue Admin, UUID explícitos y contraseñas ficticias generadas solo durante la prueba. Incluyen autenticación, inscripción de cuatro dispositivos, aislamiento/anonimato, tarifas y permisos, recepción/autorización, precios ocultos, reserva/subida/verificación de JPG, descarga privada de oficina/otro operario, denegación de GET/signed URL/reemplazo/borrado, dos cronómetros concurrentes/reintento, resolución del registro rechazado, cierre con cuatro confirmaciones, nota determinista de 3300 céntimos, exportación v7 y revocación del acceso con JWT aún vigente. No se inició sesión con la persona administradora ni se probó una cámara.

El ensayo detectó que la CDN podía servir una fotografía ya descargada tras revocar la sesión; se conservan el hallazgo y sus cabeceras en evidence/. La descarga final usa POST sin caché, autorización SQL antes/después y lectura de servidor. Storage no admite SELECT de clientes: autorizar get_authenticated_info permitía también GET, por lo que se retiró completamente esa política. Se repitió el recorrido con un archivo nuevo y la revocación pasó. Solo existían imágenes ficticias durante estos ensayos.

Limpieza confirmada: cinco cuentas bloqueadas, cero sesiones, cero pertenencias y equipos de prueba activos, servicio temporal limitado a 410 sin cliente administrativo, credenciales efímeras eliminadas. La administradora del taller piloto sigue activa. Los documentos de prueba y sus tres JPEG (1857 bytes) quedan protegidos en talleres aislados inactivos. No cambió el plan Free.

El commit 6d8fbae ya compiló Windows/Android/iOS simulador en run 37543505529, con ZIP/hashes y source-commit.json verificados. Incluye CSV pero precede a las copias divididas y a la nueva descarga; se conserva como evidencia histórica. La prueba Windows previa ejercitó tiempos y almacenamiento, sin fotografías. Se ha ampliado el ensayo nativo para fotos pendientes y recuperación de partes bajo otra clave; su ejecución del código actual queda pendiente.

## Inspecciones · 7 de octubre

Migración 013 aplicada en el proyecto principal. Seis pruebas Flutter, ocho PostgreSQL locales y diez SQL alojadas aprobaron versiones, reintentos, conflictos, permisos, exportación e historial técnico sin datos del destinatario. Las pruebas SQL alojadas emplearon identidades sintéticas y se revirtieron; no acreditan Auth HTTP ni cámara. Batería completa: 96 Flutter, 130 PostgreSQL y 18 servicios simulados. Analizador limpio.

## Recuperación alojada y retirada · 7 de octubre

Diez comprobaciones HTTP reales entre gpseuqmzbazifmkhjyby y qnbgbgumvxmmipjlkcgb (Free, coste confirmado 0 USD/mes). Dos UUID Auth originales recreados con contraseñas ficticias distintas. Se conservan documentos, operaciones, auditoría, fotografías originales y versiones de inspección; reintentos no duplican la restauración y los equipos históricos quedan retirados. Cuatro identidades Auth de prueba retiradas, cero sesiones/pertenencias/equipos activos, servicios temporales sustituidos por respuesta 410 y credenciales efímeras eliminadas. El circuito nativo Windows f9aeed3 también pasó fotos/copia/restauración entre dos procesos, con servidor ficticio.

## Modelo inicial de presupuestos

Seis pruebas de dominio de versiones inmutables, importes decimales con descuentos antes del IVA, rechazo de enlaces/versiones antiguos, caducidad, cambios de destinatario o alcance, decisiones por partida y permisos locales de oficina. El modelo es una base sin integración con pantallas, operaciones persistidas, permisos del servidor o portal; no concede autorizaciones de reparación.

## Corrección del entorno iOS

El primer proceso iOS pasó, pero Flutter elimina por defecto la aplicación de integración al terminar cada prueba (`IntegrationTestDevice.kill`, opción `uninstall`). Eso eliminó el contenedor antes del segundo proceso. La prueba de reinicio se repite con `--no-uninstall`, manteniendo los archivos originales sin copiarlos ni reinyectarlos. El fallo inicial permanece en evidencia; todavía no se da iOS por validado.
