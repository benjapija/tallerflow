# Producto y arquitectura · 0.2

España está confirmada. TallerFlow sustituye papel y programas antiguos; no se ha identificado un programa concreto ni un proveedor de documentación técnica contratado. Se mantienen Flutter/Dart, Supabase y aplicaciones nativas para operario, oficina y administrador. El portal, la IA y la facturación fiscal definitiva quedan fuera de este bloque.

## Datos y comunicación

La aplicación nativa conserva un diario cifrado por cuenta y taller, con cola de operaciones, comandos pendientes, bloqueos de cierre e historial de respuestas. Usa la misma protección nativa para claves y sesión que 0.1. El formato local 2 lee el formato 1 sin eliminar pendientes.

Al actualizar, descarga una base del servidor incluso con operaciones pendientes y reconstruye la proyección local aplicándolas por identificador. Las aceptadas, tardías o resueltas se retiran de la cola solo tras guardar la confirmación. Si un registro no puede proyectarse, su original sigue disponible y se envía para revisión; no se interpreta como trabajo inexistente. Las incidencias que el servidor ya conserva no bloquean el envío de otros registros independientes.

Los cambios de oficina necesitan la revisión correspondiente. Resolver un conflicto crea una corrección con identificador nuevo, motivo, responsable y enlace al original. El actor original se conserva; el servidor vuelve a validar su permiso y las reglas actuales. La alternativa de conservar sin aplicar tampoco elimina la evidencia. Los originales y resoluciones tienen protección contra modificación y borrado.

Supabase usa tablas privadas con RLS y APIs autenticadas, sin escritura directa del cliente. Las funciones privilegiadas cualifican objetos y fijan `search_path` vacío. La API de registro sigue obteniendo precios del catálogo del servidor. Los céntimos, cantidades en milésimas e impuestos se calculan con enteros y redondeo por línea; las notas emitidas guardan su instantánea.

Las llamadas de datos tienen límite de espera; un timeout puede ocurrir después de una confirmación del servidor, por lo que no significa cancelación. Operaciones y comandos conservan su identificador al reintentar. Los cambios de sincronización y el recibo de un comando se guardan de forma atómica; un fallo de escritura conserva la evidencia y el intento.

## Sesiones y dispositivos

La sesión local permite reabrir trabajos descargados de la misma cuenta durante 24 horas desde la validación. Se comprueba el reloj y se exige revalidación al recuperar conexión. Una revocación offline se conoce al reconectar o al vencer ese plazo; no se promete retirada instantánea de datos de un equipo desconectado.

La identidad del dispositivo se vincula al `session_id` firmado de Supabase. Se conserva el historial de sesiones vinculadas, y la API verifica que la sesión todavía existe en `auth.sessions`. Una sesión de un equipo retirado no puede registrar otro identificador para recuperar escritura. Sustituirlo exige una sesión nueva de la misma cuenta. Referencia: [sesiones y comprobación de cierre de sesión de Supabase](https://supabase.com/docs/guides/auth/sessions).

Un inicio de sesión nuevo en un equipo activo revalida su vínculo e invalida solicitudes de cierre afectadas. Retirar el equipo conserva sus inscripciones y registros, revoca su capacidad de modificar y exige revisión de cualquier evidencia recuperada. No desactiva por sí mismo la cuenta del operario en otros equipos.

## Cierre conectado implementado

1. `device_snapshot` registra cada dispositivo que descarga órdenes con capacidad de modificación. Una inscripción nueva invalida un cierre pendiente.
2. Oficina solicita cierre sobre una revisión concreta. Existe una única solicitud activa por orden.
3. Cada equipo reconcilia su cola y detiene sus cronómetros. Si eso cambia la orden, hay que renovar la solicitud.
4. El cliente guarda el bloqueo local antes de enviar su confirmación, vinculada a solicitud y revisión. Ese bloqueo sobrevive a reapertura; la ausencia de una solicitud en una respuesta no se interpreta como cancelación.
5. Un cambio, conflicto, registro recuperado, revalidación de identidad o retirada invalida solicitudes afectadas. Confirmaciones antiguas no confirman una solicitud nueva.
6. El servidor comprueba todos los equipos inscritos, revisiones, cronómetros, tareas, autorizaciones, movimientos revisados, stock y calidad. Calcula e inserta el documento, actualiza la orden y marca la solicitud emitida en una transacción serializada por taller.
7. La fila de documento y la instantánea de la orden quedan protegidas contra cambios. Los registros posteriores son incidencias, y no sustituyen importes o contenido.

La antigua operación `issue` continúa bloqueada: no permite eludir este circuito. El cliente 0.2 emite mediante `reliability_command` después de confirmar. No hay una excepción automática por antigüedad o desconexión de dispositivos.

## Retiradas y excepciones

Oficina o administrador puede retirar otro equipo con motivo y auditoría. Las solicitudes afectadas se invalidan. Los cronómetros activos no reciben una duración inventada: oficina debe registrar un fin real con motivo y soporte humano, preservando su autor.

Solo administrador puede solicitar una excepción por equipos retirados. Se enumeran los equipos exceptuados y se guarda el motivo en solicitud, auditoría y documento. El resto de condiciones del cierre sigue siendo obligatorio. Una retirada no se registra como confirmación de envío.

La recuperación permite conservar evidencia original de equipos retirados, incluso una recepción que nunca llegó al servidor. No vuelve a conceder capacidad de edición al equipo anterior ni permite incorporar datos tardíos a documentos emitidos.

## Estado y fases

El bloque de fiabilidad 0.2 está implementado y probado localmente. Falta validar Supabase/Auth alojado y dispositivos físicos. La simulación utiliza el controlador y las pantallas Flutter con un servidor en memoria; no sustituye las pruebas PostgreSQL ni una instalación real.

**Resto de fase 1:** administración de cuentas/permisos/tarifas/impuestos/catálogo/plantillas, edición y reasignación completa de tareas y operarios, prioridades y bloqueos, historial consolidado y privacidad ante cambio de propietario, descuentos y precios revisables con motivo, consumos sin cobro, costes/margen estimado, fotos/Storage, QR con cámara y enlaces nativos. Exportación, copia y restauración completas son condiciones anteriores a datos reales.

**Fase 2:** inspección completa, presupuestos versionados, portal HTTPS con destinatario verificado, autorización digital, almacén/compras, garantías, PDF y pagos.

**Fase 3:** IA técnica y administrativa, cuaderno de diagnóstico, biblioteca validada, dictado y lectura con cámara. Requiere fuentes autorizadas, licencia y revisión humana; no calculará importes.

**Fase 4:** agenda, mantenimiento, flotas e integraciones tras confirmar necesidad, APIs y contratos. La facturación fiscal española requiere concretar obligaciones del taller antes de implementarla.
