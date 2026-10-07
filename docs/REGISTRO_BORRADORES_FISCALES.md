# Registro persistente de borradores · documento de trabajo

7 de octubre de 2026. Disponible en el servidor de pruebas, principal y recuperación. **Sin emisión ni transmisión fiscal.** Su interfaz de aplicación aún está pendiente.

Cada borrador tiene un identificador estable, autor, dispositivo, motivo y cálculo conservado. El servidor calcula bases y cuotas con cantidades de milésimas, descuento previo y redondeo por partida. Solo se aceptan series `ENSAYO-…`; sus números nunca se presentan como números de factura.

La cadena se separa por taller, emisor e instalación. Las series mantienen contadores propios dentro de esa cadena. La transacción bloquea primero el taller, comprueba el estado anterior esperado y guarda registro, contador, recibo y auditoría juntos. Un reintento con el mismo identificador y contenido devuelve el mismo resultado. Reutilizarlo con otros datos se rechaza. Un conflicto exige actualizar y revisar antes de crear otro borrador.

Retirar un borrador añade otro registro con motivo y referencia al original. Conserva el contenido y no recicla su número. **Esta retirada no es una anulación fiscal.** Los registros no se pueden editar ni borrar mediante las funciones de la aplicación.

## Acceso y copias

Los comandos y la consulta requieren administrador, sesión Auth vigente y dispositivo activo. Oficina, operario, otro taller y acceso anónimo se deniegan. Las tablas privadas tienen RLS y carecen de permisos directos para clientes; las funciones autorizadas vuelven a comprobar la identidad y el dispositivo.

La copia de servidor pasa a **formato 14** e incluye cabeceras, series, registros, recibos y auditoría. La recuperación verifica cadena, cálculos, contadores, referencias y autores. Una omisión o incoherencia revierte toda la restauración. Las copias 2–13 sin borradores siguen siendo compatibles; no se permite ocultar registros nuevos en una versión antigua.

Tras recuperar, las instalaciones antiguas quedan congeladas. Se conservan sus documentos de prueba y su numeración, pero una instalación nueva de ensayo empieza otra cadena. El reintento de una restauración terminada no congela instalaciones creadas posteriormente. La continuidad de una instalación **fiscal real** requiere otro circuito todavía pendiente.

## Huellas y validación

`ledger_hash` utiliza SHA-256 con dominio `TALLERFLOW-DRAFT-1`, contenido JSON conservado y huella anterior. Sirve para comprobar coherencia del registro de ensayo. **No es la huella VERI*FACTU**, ni una firma electrónica, ni una prueba de aceptación por Hacienda. El adaptador AEAT local sigue separado; no se almacena un XML enviado ni una respuesta oficial.

24 comprobaciones nuevas en PostgreSQL/PGlite; batería completa 295 PostgreSQL, 43 servicios simulados y cinco del portal. Restauración en dos bases locales independientes, reintentos, conflictos, permisos, originales, omisiones y legado. Dos llamadas en cola en PGlite no acreditan una carrera entre conexiones PostgreSQL independientes.

En cada Supabase: 16 comprobaciones SQL, identidades Auth sintéticas y rollback completo. No son inicios de sesión GoTrue ni peticiones HTTP del cliente. Once pruebas Flutter de copias se repitieron; siguen incluidas en las 243 de la batería anterior. No se generaron nuevas aplicaciones nativas: el cliente y la demo continúan en 6be045d.

## Pendientes

Interfaz y cola local de borradores, integración con el adaptador XML, pruebas HTTP con Auth real, recuperación formato 14 entre proyectos y concurrencia entre conexiones. Después, numeración/series fiscales, continuidad real, documentos completos, rectificaciones, validaciones de negocio, transportes y pruebas oficiales. Las notas y PDF actuales siguen siendo documentos de trabajo; IA real desactivada y recursos gratuitos.

Referencias de implementación: [funciones de Supabase](https://supabase.com/docs/guides/database/functions), [RLS y permisos](https://supabase.com/docs/guides/database/postgres/row-level-security), [bloqueos de PostgreSQL](https://www.postgresql.org/docs/current/explicit-locking.html). Alcance fiscal oficial en [MOTOR_FISCAL_EN_DESARROLLO.md](MOTOR_FISCAL_EN_DESARROLLO.md).
