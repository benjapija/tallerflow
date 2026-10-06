# Fiabilidad y prueba desde Mac · 0.2

## Qué puedes comprobar ahora

La demo del navegador usa tres clientes Flutter independientes y un servidor ficticio en memoria. Puedes revisar el recorrido sin cuentas, contratos ni gastos. No sustituye las pruebas entre tres equipos físicos ni contra Supabase alojado.

Abre el paquete web y ejecuta `Abrir TallerFlow.command`. En Configuración pulsa **Probar dos móviles y oficina**. El encabezado amarillo identifica siempre la simulación. Cada móvil tiene su propia cola y su propio estado de conexión. La reparación de ejemplo **Renault Kangoo** está asignada a ambos operarios y preparada para revisar el cierre.

### Cierre normal

1. En oficina abre Renault Kangoo y solicita cierre.
2. Confirma el dispositivo de oficina. Observa que siguen faltando los móviles.
3. Cambia a Álex, actualiza, abre Renault y confirma. Haz lo mismo con Lucía.
4. Vuelve a oficina, actualiza y emite la nota. Debe conservarse un total de **43,56 €** en este ejemplo.
5. Los registros de trabajo quedan bloqueados en los dispositivos confirmados; ese bloqueo se guarda antes de enviar la confirmación.

Para la prueba negativa, desconecta Lucía antes de confirmar. Aunque oficina haya enviado todo, el cierre debe permanecer bloqueado. Reconecta y actualiza después. No renueves la solicitud si quieres conservar las confirmaciones actuales: renovarla cancela la anterior y exige confirmar de nuevo.

### Cambio durante una solicitud

Solicita cierre antes de confirmar un móvil. Desde ese móvil registra una observación y sincroniza. Oficina debe ver la solicitud invalidada y pedir una nueva sobre la revisión actual. Una confirmación antigua nunca confirma esa nueva solicitud.

Si hay un cronómetro activo, el técnico debe pausarlo y sincronizarlo. Ese cambio invalida el cierre solicitado y requiere renovarlo. La app no interpreta una conexión activa o una cola vacía como evidencia de todos los dispositivos.

### Conflictos

En oficina, abre **Revisión** y consulta los originales conservados. Puedes:

- **Revisar y aplicar registro:** crea una corrección vinculada, conserva el autor original y vuelve a comprobar permisos, autorización, tiempo, revisión y stock. Si sigue siendo inválido, la resolución no se da por terminada.
- **Conservar sin aplicar, con motivo:** mantiene la evidencia y registra el motivo y seguimiento. No incorpora ese trabajo a cantidades o cobros por sí solo.

La lista muestra responsable, resultado y motivo de cada resolución. Un registro tardío no se incorpora a una nota emitida: se conserva para seguimiento o una corrección posterior trazable. El desarrollo de documentos sustitutivos completos sigue pendiente.

Para generar un conflicto de revisión en la simulación, deja oficina desconectada después de descargar una orden, registra trabajo desde un móvil y reconéctala para enviar una revisión basada en la versión antigua. Para probar stock puedes registrar consumos superiores a la existencia disponible en una tarea autorizada. El original queda pendiente, sin descontar stock por segunda vez ni ocultarlo.

## Política de sesión local

La aplicación nativa puede abrir los trabajos descargados de la **misma cuenta** usando el almacén cifrado y los permisos obtenidos del servidor. No solicita primero el perfil remoto. Una cuenta nueva necesita conexión y autenticación.

La autorización local dura **24 horas desde la última validación del servidor**. El vencimiento bloquea lectura y edición de las pantallas de trabajo y conserva los registros pendientes. Retroceder el reloj más de dos minutos respecto a los tiempos guardados también bloquea el uso. Una validación nueva requiere que el reloj del equipo coincida con el servidor dentro de dos minutos.

Al recuperar conexión se verifica la pertenencia, se descarga la política actual y se reconcilian los registros. Hay actualización periódica cada 30 segundos y al volver a la app. Los errores de transporte no renuevan la autorización local. Las llamadas de datos tienen un límite de espera de 12 segundos y conservan sus identificadores para reintentar.

**Una revocación no llega instantáneamente a un equipo sin conexión.** El servidor la aplica en sus APIs; el cliente se bloquea cuando la recibe o cuando vence su autorización local. Esta entrega depende del reloj del sistema y no ofrece resistencia frente a manipulación de un dispositivo comprometido. La política deberá probarse y aceptarse en los equipos del taller antes del piloto.

Las sesiones y claves se almacenan en el almacén seguro nativo. Los archivos locales se cifran y se guardan mediante rotación atómica. Una clave ausente o un archivo alterado no se interpreta como una base vacía. Las pruebas comprueban estas reglas mediante almacenes de prueba y archivos temporales; los plugins nativos necesitan comprobación física.

## Retirada y sustitución

1. Desde otro equipo de oficina o administrador, abre Revisión → Dispositivos del taller → Retirar. Introduce motivo de pérdida o sustitución.
2. El servidor mantiene la identidad y su historial, bloquea sus sesiones de acceso vinculadas e invalida las solicitudes afectadas. No elimina su inscripción en las órdenes ni la convierte en confirmación.
3. Si dejó un cronómetro activo, oficina usa **Registrar fin real**, con motivo, fecha y hora respaldados por la revisión humana. La retirada no inventa duración ni minutos facturables.
4. Si se recupera el equipo, la pantalla bloqueada permite enviar sus registros pendientes como evidencia para oficina. Si hace falta renovar la autenticación, usa **Iniciar sesión de nuevo** con la misma cuenta. Estos registros no modifican una nota emitida.
5. Con los pendientes recuperados, pulsa **Registrar dispositivo sustituto**. En una instalación real se exige una sesión nueva de la misma cuenta; se crea una identidad distinta. Las sesiones anteriores del equipo retirado no pueden registrar otra identidad para recuperar capacidad de editar.
6. Oficina revisa las incidencias. Si un equipo retirado tiene datos irrecuperables, el cierre normal sigue bloqueado. Solo administrador puede solicitar una **excepción de cierre**, indicando motivo y seguimiento. Esa excepción queda en solicitud, auditoría y nota. No afirma que los registros perdidos estuvieran sincronizados.

La simulación sustituye autenticación y reloj de red por datos ficticios. La relación con sesiones JWT y `auth.sessions` se comprueba en PostgreSQL con Auth simulado y necesita validación alojada. Referencia del diseño: [sesiones de Supabase](https://supabase.com/docs/guides/auth/sessions).

Una base antigua 0.1 sin sesiones vinculadas requiere una migración supervisada y revocar sus sesiones en Auth antes de reutilizar dispositivos. Este proyecto no tuvo un Supabase alojado configurado en 0.1.

## Comprobaciones externas obligatorias

- Supabase de pruebas: Auth real, sesiones independientes, permisos y almacenamiento; retiradas, reinicios y errores HTTP.
- Dos móviles y oficina: trabajar sin red, cerrar app, reiniciar físicamente y cotejar diarios y documentos.
- iOS/Android/macOS: permisos, clave segura, cambios de reloj, bloqueo del equipo y recuperación.
- Windows: ejecutar GitHub Actions, descargar instalador desde Mac y comprobar manualmente instalación, escalado, teclado, suspensión, red y actualización en Windows remoto.
- Exportación y copia completa restaurada en otro entorno, incluyendo los pendientes locales.

No utilices datos reales hasta completar estas comprobaciones y los requisitos restantes de fase 1.
