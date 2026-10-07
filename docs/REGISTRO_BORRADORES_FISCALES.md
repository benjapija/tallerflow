# Registro de ensayos · documento de trabajo

Corte: 7 de octubre de 2026, 18:02, España peninsular. Servidor instalado en Supabase principal y recuperación; **interfaz y cola integradas en la fuente local**, pendientes de publicar/compilar y validar desde aplicaciones con Supabase. **Sin emisión ni transmisión fiscal.** El cliente nativo anterior 6be045d no contiene estas pantallas nuevas.

## Originales y cadena del servidor

Cada ensayo tiene identificador estable, autor, dispositivo, motivo y cálculo conservado. El servidor calcula bases/cuotas con cantidades de milésimas, descuento previo y redondeo por partida. Solo se aceptan series `ENSAYO-…`; sus números no son números de factura.

La cadena se separa por taller, emisor e instalación. Las series mantienen contadores propios dentro de esa cadena. La transacción bloquea primero el taller, comprueba la cabecera anterior esperada y guarda registro, contador, recibo y auditoría juntos. Reintentar el mismo identificador y contenido devuelve el mismo resultado. Reutilizar el identificador con otros datos se rechaza. Un conflicto exige consultar y revisar antes de preparar otra solicitud.

Una retirada agrega un registro con motivo y referencia al original. No cambia el contenido ni recicla su número. **No representa una anulación fiscal.** Los originales no se editan ni borran mediante las funciones de la aplicación.

## Circuito de aplicación implementado

Desde **Configuración y puesta en marcha → Registro de ensayos**, un administrador con sesión/dispositivo activos utiliza **Actualizar registro** para obtener la cadena autorizada y validarla. El cliente conserva cabeceras, series y originales; verifica cálculos, huellas internas y correspondencia de confirmaciones. La demo utiliza datos ficticios y no confirma documentos contra Supabase.

**Preparar ensayo** exige revisión de emisor, instalación, serie de ensayo, fecha, destinatario, partidas/impuestos y motivo. La preparación actual protege el límite del circuito: SII declarado distinto de «no», territorio foral o desconocido no eligen silenciosamente este adaptador. La selección del perfil no determina las obligaciones fiscales del cliente.

La solicitud se guarda antes de enviarse, con UUID, autor, dispositivo, acción, contenido y cabecera esperada. Mientras es local muestra **Ensayo local · sin confirmación del servidor** e **Identificador conservado**; no se le atribuye un número confirmado. Para preparar sin conexión se necesita haber obtenido antes una vista autorizada; siguen aplicándose vigencia/retirada de acceso del almacén local.

La consulta usa `public.fiscal_drafts(workshop_id, device_id)`. Los comandos `fiscal_draft_append` y `fiscal_draft_withdraw` se envían mediante `public.fiscal_draft_command(workshop_id, device_id, command_id, action, payload)`. No se usan nombres RPC alternativos ni se envía un comando fiscal por el circuito ordinario de órdenes. Consulta y comandos vuelven a comprobar Auth, miembro, rol y dispositivo en el servidor.

### Reintentos, conflictos y acceso

- El cliente consulta primero. Si el servidor ya conserva el mismo UUID y contenido después de una respuesta perdida, recupera su recibo y marca **Confirmado por el servidor** sin crear otra solicitud.
- **Reintentar misma solicitud** conserva UUID, payload y cabecera esperada. Un error de transporte/gateway, respuesta incompleta o fallo de persistencia posterior al envío mantiene la confirmación incierta: no equivale a un rechazo ni permite numerar de nuevo.
- Un rechazo transaccional de negocio/entrada o conflicto se conserva para revisión. Un pendiente, conflicto o rechazo sin revisar impide encadenar otra solicitud de la misma instalación. **Registrar revisión** exige motivo y conserva el original; no sustituye automáticamente la cabecera esperada ni archiva una respuesta incierta como si estuviera rechazada.
- Un rechazo de acceso durante consulta o envío revoca la disponibilidad local y conserva el pendiente. Oficina/operario no ven la administración de ensayos. Una copia que contenga caché fiscal restringida, incluso dentro de evidencia de recuperación, necesita administrador para exportarse.
- **Retirar ensayo** crea la nueva solicitud ligada al original y con motivo; la confirmación conserva secuencia, número, autor, dispositivo y huella. No borra el ensayo ni constituye una comunicación fiscal.

## Almacén local cifrado y copia

`localArchive()` incorpora `fiscalDraftLedger`, `fiscalDraftQueue`, `fiscalDraftXmlArtifacts` y el estado de consulta. El almacén nativo cifra el conjunto con AES-GCM y clave guardada en el almacenamiento seguro del sistema. Su escritura rota archivos temporal/anterior y el controlador revierte el cambio en memoria si falla la persistencia. Las pruebas locales verifican recuperación y errores; queda comprobar la nueva interfaz en cada plataforma real.

Al reabrir se validan identidades, acciones/estados, payload normalizado, originales de solicitudes confirmadas y artefactos XML asociados. Una confirmación local sin original verificable se rechaza. No se descarta una solicitud para hacer pasar una copia corrupta.

La copia de **servidor formato 14** incluye cabeceras, series, registros, recibos y auditoría. La copia portable de la aplicación añade el almacén local, sus pendientes y XML conservados, junto a documentos/fotos. Estos números de formato pertenecen a capas distintas; no implican una nueva versión del formato de factura.

La recuperación de servidor verifica cadena, cálculos, contadores, referencias y autores; una omisión/incoherencia revierte toda la restauración. Las copias 2–13 sin ensayos siguen compatibles, sin permitir esconder datos nuevos en una versión antigua.

Después de recuperar, las instalaciones antiguas quedan **congeladas**: sus documentos y números se conservan. Una instalación de ensayo nueva empieza otra cadena. Reintentar una recuperación terminada no congela instalaciones creadas después. En el cliente, sustituir el dispositivo conserva durablemente el dispositivo de origen de todas las filas de la cola. Un pendiente de otro dispositivo no se reenvía bajo una identidad nueva; se contrasta el original y se conserva para revisión. La continuidad de una instalación **fiscal real** sigue pendiente.

## Huellas y XML

`ledger_hash` es SHA-256 con dominio `TALLERFLOW-DRAFT-1`, representación JSON conservada y huella anterior. Comprueba coherencia interna del ensayo. **No es la huella VERI*FACTU, una firma electrónica ni una aceptación de Hacienda.** No demuestra por sí sola el origen de datos: la vista de origen requiere consulta autenticada y autorizada.

La pantalla **XML técnicos de ensayo** genera una proyección local desde originales confirmados, conserva snapshot, identidad/versión técnica y bytes exactos, y permite guardarlos por selector. Los XML se cifran dentro del almacén de la aplicación y viajan en su copia; **todavía no se persisten ni comparten como originales XML del servidor**. La exportación `.xml` elegida por el usuario contiene bytes UTF-8 normales. Véase [XML_BORRADORES_CONFIRMADOS.md](XML_BORRADORES_CONFIRMADOS.md).

## Evidencia y trabajo restante

La última batería global local cerrada tiene **329 Flutter**, analizador limpio y web release aprobada. Incluye pruebas de cola/controlador, permisos/reinicio/dispositivo recuperado, widgets, API simulada, XML y copias; no son inicios de sesión desde aplicaciones nativas. Las veinte reglas nuevas de documentos son dominio local sin pantalla ni contrato SQL de sus campos; están en revisión adicional y necesitan repetir pruebas tras sus cambios.

La batería Node de este corte aprobó 29 suites: **295 PostgreSQL/PGlite y tres vectores independientes de huella**, 43 servicios simulados y cinco del portal. El registro aporta 24 comprobaciones de servidor dentro de ese total. Además, 13 comprobaciones VM y diez XSD locales contrastan proyección y bytes ficticios; no se suman como nuevos Flutter.

Evidencia alojada previa conservada: 16 comprobaciones SQL por Supabase, Auth sintético y rollback; **13 HTTP de ensayos con GoTrue real y once de recuperación formato 14 entre proyectos**, dentro de las 51 HTTP del recorrido global. Peticiones HTTP superpuestas/reintentos conservan un efecto; no se observaron IDs internos de procesos PostgreSQL. La recuperación conservó cuatro registros, fotos/módulos y congelación correcta. Diez cuentas ficticias retiradas, cero sesiones/miembros/dispositivos de pruebas activos, servicios temporales HTTP 410 y capacidad eliminada. Véase `evidence/fiscal14-hosted-summary.json`. No acredita la interfaz nativa nueva.

Pendientes: publicación/compilación común y [recorridos nativos](RECORRIDOS_PILOTO_NATIVO.md); persistencia compartida de XML, nuevos campos/circuitos de documentos, series/continuidad fiscales reales, rectificaciones completas, adaptadores, transporte/respuestas y pruebas oficiales. Notas/PDF siguen como documentos de trabajo, IA real desactivada y recursos gratuitos. El proyecto no está terminado.

Referencias: [funciones Supabase](https://supabase.com/docs/guides/database/functions), [RLS y permisos](https://supabase.com/docs/guides/database/postgres/row-level-security), [bloqueos PostgreSQL](https://www.postgresql.org/docs/current/explicit-locking.html) y [motor fiscal en desarrollo](MOTOR_FISCAL_EN_DESARROLLO.md).
